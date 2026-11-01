use std::{
    io::{Cursor, Write},
    time::Duration,
};

use base64::{Engine, engine::general_purpose::STANDARD};
use otter_core::{
    error::ErrorCode,
    network,
    ocr::{self, MineruOptions, OcrClient, PaddleOptions},
};
use serde_json::{Value, json};
use tempfile::tempdir;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
};
use tokio_util::sync::CancellationToken;
use zip::{ZipWriter, write::SimpleFileOptions};

struct Request {
    head: String,
    body: Vec<u8>,
}
async fn server(
    responses: impl FnOnce(&str) -> Vec<Vec<u8>>,
) -> (String, tokio::task::JoinHandle<Vec<Request>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let responses = responses(&base);
    let handle = tokio::spawn(async move {
        let mut requests = Vec::new();
        for body in responses {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut bytes = Vec::new();
            let mut buffer = [0; 4096];
            let (end, length) = loop {
                let count = socket.read(&mut buffer).await.unwrap();
                assert_ne!(count, 0);
                bytes.extend_from_slice(&buffer[..count]);
                if let Some(start) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
                    let head = String::from_utf8_lossy(&bytes[..start]);
                    let length = head
                        .lines()
                        .find_map(|line| {
                            line.to_ascii_lowercase()
                                .strip_prefix("content-length:")
                                .and_then(|v| v.trim().parse::<usize>().ok())
                        })
                        .unwrap_or(0);
                    break (start + 4, length);
                }
            };
            while bytes.len() < end + length {
                let count = socket.read(&mut buffer).await.unwrap();
                assert_ne!(count, 0);
                bytes.extend_from_slice(&buffer[..count]);
            }
            requests.push(Request {
                head: String::from_utf8(bytes[..end].to_vec()).unwrap(),
                body: bytes[end..end + length].to_vec(),
            });
            socket
                .write_all(
                    format!(
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        body.len()
                    )
                    .as_bytes(),
                )
                .await
                .unwrap();
            socket.write_all(&body).await.unwrap();
        }
        requests
    });
    (base, handle)
}

fn zip(entries: &[(&str, &[u8])]) -> Vec<u8> {
    let mut archive = ZipWriter::new(Cursor::new(Vec::new()));
    for (name, bytes) in entries {
        archive
            .start_file(name, SimpleFileOptions::default())
            .unwrap();
        archive.write_all(bytes).unwrap();
    }
    archive.finish().unwrap().into_inner()
}

#[tokio::test]
async fn paddle_posts_actual_pdf_and_options_and_decodes_provider_response() {
    let root = tempdir().unwrap();
    let pdf = root.path().join("source.pdf");
    tokio::fs::write(&pdf, b"%PDF-1.7\nnetwork payload")
        .await
        .unwrap();
    let raw = json!({"errorCode":0,"result":{"layoutParsingResults":[{"page_size":[600,800],"prunedResult":{"parsing_res_list":[{"block_id":1,"block_label":"text","block_content":"OCR body","block_bbox":[1,2,300,40]}]},"markdown":{"text":"OCR body","images":{}}}]}});
    let (base, requests) = server(|_| vec![serde_json::to_vec(&raw).unwrap()]).await;
    let client = OcrClient::new(network::client(None, false).unwrap());
    let result = client
        .paddle(
            &pdf,
            &base,
            "local-test-token",
            &PaddleOptions::default(),
            &CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(result.model.blocks[0].text, "OCR body");
    let requests = requests.await.unwrap();
    assert!(requests[0].head.starts_with("POST /layout-parsing "));
    assert!(requests[0].head.contains("token local-test-token"));
    let body: Value = serde_json::from_slice(&requests[0].body).unwrap();
    assert_eq!(
        STANDARD.decode(body["file"].as_str().unwrap()).unwrap(),
        tokio::fs::read(pdf).await.unwrap()
    );
    assert_eq!(body["useLayoutDetection"], true);
    assert_eq!(body["restructurePages"], true);
    assert_eq!(body["fileType"], 0);
}

#[tokio::test]
async fn paddle_job_uploads_real_pdf_polls_and_downloads_ordered_jsonl_without_leaking_key() {
    let root = tempdir().unwrap();
    let pdf = root.path().join("source.pdf");
    tokio::fs::write(&pdf, include_bytes!("fixtures/two_pages.pdf"))
        .await
        .unwrap();
    let (base, requests) = server(|base| vec![
        json!({"code":0,"data":{"jobId":"job-1"}}).to_string().into_bytes(),
        json!({"code":0,"data":{"state":"running","extractProgress":{"extractedPages":"1","totalPages":2}}}).to_string().into_bytes(),
        json!({"code":0,"data":{"state":"done","resultUrl":{"jsonUrl":format!("{base}/result.jsonl")}}}).to_string().into_bytes(),
        (0..2).map(|page| json!({"result":{"layoutParsingResults":[{"page_size":[600,800],"prunedResult":{"parsing_res_list":[{"block_id":0,"block_label":"text","block_content":format!("Page {}",page+1),"block_bbox":[1,2,300,40]}]},"markdown":{"text":format!("Page {}",page+1),"images":{}}}]}}).to_string()).collect::<Vec<_>>().join("\n").into_bytes(),
    ]).await;
    let mut client = OcrClient::new(network::client(Some(""), false).unwrap());
    client.poll_interval = Duration::from_millis(1);
    let mut events = Vec::new();
    let output = client
        .paddle_job(
            &pdf,
            &format!("{base}/jobs"),
            "local-job-key",
            &PaddleOptions::default(),
            &CancellationToken::new(),
            |progress| events.push(progress),
        )
        .await
        .unwrap();
    assert_eq!(output.raw_markdown, "Page 1\n\nPage 2");
    assert_eq!(output.structure.pages.len(), 2);
    assert!(
        events
            .iter()
            .any(|event| event.done == 1 && event.total == 2)
    );
    let requests = requests.await.unwrap();
    assert!(requests[0].head.starts_with("POST /jobs "));
    assert!(requests[0].head.contains("bearer local-job-key"));
    assert!(
        requests[0]
            .body
            .windows(include_bytes!("fixtures/two_pages.pdf").len())
            .any(|part| part == include_bytes!("fixtures/two_pages.pdf"))
    );
    assert!(requests[1].head.starts_with("GET /jobs/job-1 "));
    assert!(!requests[3].head.to_lowercase().contains("authorization:"));
    let storage = otter_core::storage::Storage::open(root.path()).unwrap();
    ocr::usage::record(&storage, output.provider, 2).unwrap();
    assert_eq!(ocr::usage::today(&storage).unwrap().paddle, 2);
    storage
        .put_setting(
            "doc_extract_usage",
            &json!({"date":"2000-01-01","paddle":999}),
        )
        .unwrap();
    assert_eq!(ocr::usage::today(&storage).unwrap().paddle, 0);
}

#[tokio::test]
async fn paddle_job_returns_quota_error_and_cancellation_stops_polling() {
    let root = tempdir().unwrap();
    let pdf = root.path().join("source.pdf");
    tokio::fs::write(&pdf, include_bytes!("fixtures/two_pages.pdf"))
        .await
        .unwrap();
    let (base, requests) = server(|_| vec![json!({"code":12001}).to_string().into_bytes()]).await;
    let mut client = OcrClient::new(network::client(Some(""), false).unwrap());
    client.poll_interval = Duration::from_millis(1);
    assert_eq!(
        client
            .paddle_job(
                &pdf,
                &base,
                "local-key",
                &PaddleOptions::default(),
                &CancellationToken::new(),
                |_| {}
            )
            .await
            .err()
            .unwrap()
            .code,
        ErrorCode::QuotaExceeded
    );
    requests.await.unwrap();
    let (base, requests) = server(|_| {
        vec![
            json!({"code":0,"data":{"jobId":"pending"}})
                .to_string()
                .into_bytes(),
            json!({"code":0,"data":{"state":"running"}})
                .to_string()
                .into_bytes(),
        ]
    })
    .await;
    let token = CancellationToken::new();
    let cancel = token.clone();
    let result = client
        .paddle_job(
            &pdf,
            &base,
            "local-key",
            &PaddleOptions::default(),
            &token,
            |progress| {
                if matches!(progress.stage, ocr::OcrStage::Running) {
                    cancel.cancel();
                }
            },
        )
        .await;
    assert_eq!(result.err().unwrap().code, ErrorCode::Cancelled);
    assert_eq!(requests.await.unwrap().len(), 2);
}

#[tokio::test]
async fn mineru_uploads_without_auth_to_signed_url_polls_by_data_id_and_publishes_atomically() {
    let root = tempdir().unwrap();
    let pdf = root.path().join("source.pdf");
    tokio::fs::write(&pdf, b"%PDF-1.7\nnetwork payload")
        .await
        .unwrap();
    let v2=json!([[{"type":"paragraph","content":{"paragraph_content":"Recognized body"}},{"type":"image","content":{"image_source":{"path":"images/figure.png"},"image_caption":"Figure 1. Caption."}}]]).to_string();
    let package = zip(&[
        ("full.md", b"Recognized body"),
        ("paper_content_list_v2.json", v2.as_bytes()),
        ("images/figure.png", b"image payload"),
    ]);
    let (base,requests)=server(|base|vec![
        json!({"code":0,"data":{"batch_id":"batch","file_urls":[format!("{base}/signed-upload")]}}).to_string().into_bytes(),
        vec![],json!({"code":0,"data":{"extract_result":[{"data_id":"document","state":"running"},{"data_id":"unrelated","state":"failed"}]}}).to_string().into_bytes(),
        json!({"code":0,"data":{"extract_result":[{"data_id":"document","state":"done","full_zip_url":format!("{base}/package.zip")}]}}).to_string().into_bytes(),package
    ]).await;
    let mut client = OcrClient::new(network::client(None, false).unwrap());
    client.poll_interval = Duration::from_millis(1);
    let outputs = client
        .mineru(
            &base,
            "local-secret",
            &[("document".into(), pdf.clone())],
            &MineruOptions::default(),
            &CancellationToken::new(),
            |_| {},
        )
        .await
        .unwrap();
    assert_eq!(outputs.len(), 1);
    assert_eq!(outputs[0].0, "document");
    assert_eq!(outputs[0].1.model.blocks[0].text, "Recognized body");
    assert_eq!(outputs[0].1.assets["images/figure.png"], b"image payload");
    let requests = requests.await.unwrap();
    assert!(requests[1].head.starts_with("PUT /signed-upload "));
    assert!(
        !requests[1]
            .head
            .to_ascii_lowercase()
            .contains("authorization:")
    );
    assert!(
        !requests[1]
            .head
            .to_ascii_lowercase()
            .contains("content-type:")
    );
    assert_eq!(requests[1].body, tokio::fs::read(pdf).await.unwrap());
    assert!(
        requests[2]
            .head
            .starts_with("GET /extract-results/batch/batch ")
    );
    let published = root.path().join("published");
    let generation = ocr::publish(&published, &outputs[0].1, &CancellationToken::new()).unwrap();
    let pointer = std::fs::read(published.join("ocr-current.json")).unwrap();
    assert_eq!(
        std::fs::read(
            published
                .join("ocr")
                .join(generation)
                .join("images/figure.png")
        )
        .unwrap(),
        b"image payload"
    );
    let cancel = CancellationToken::new();
    cancel.cancel();
    assert_eq!(
        ocr::publish(&published, &outputs[0].1, &cancel)
            .unwrap_err()
            .code,
        ErrorCode::Cancelled
    );
    assert_eq!(
        std::fs::read(published.join("ocr-current.json")).unwrap(),
        pointer
    );
}

#[test]
fn mineru_zip_rejects_path_traversal_before_exposing_assets() {
    let package = zip(&[("../escape", b"bad")]);
    assert!(
        matches!(ocr::mineru_package(&package,&[]),Err(error) if error.code==ErrorCode::InvalidData)
    );
}

#[tokio::test]
async fn cancellation_drops_a_live_http_request() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let token = CancellationToken::new();
    let request = network::client(None, false).unwrap().get(url);
    let cancellation = token.clone();
    let server = tokio::spawn(async move {
        let (_socket, _) = listener.accept().await.unwrap();
        cancellation.cancel();
        tokio::time::sleep(Duration::from_millis(20)).await;
    });
    let error = match network::send(request, &token).await {
        Err(e) => e,
        Ok(_) => panic!("cancelled HTTP request completed"),
    };
    assert_eq!(error.code, ErrorCode::Cancelled);
    server.await.unwrap();
}
