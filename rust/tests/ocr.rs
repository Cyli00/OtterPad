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
            None,
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
                None,
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
            None,
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
    let output = client
        .mineru_document(
            &base,
            "local-secret",
            "document",
            &pdf,
            None,
            &MineruOptions::default(),
            &CancellationToken::new(),
            |_| {},
        )
        .await
        .unwrap();
    assert_eq!(output.model.blocks[0].text, "Recognized body");
    assert_eq!(output.assets["images/figure.png"], b"image payload");

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
    let generation = ocr::publish(&published, &output, &CancellationToken::new()).unwrap();
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
        ocr::publish(&published, &output, &cancel).unwrap_err().code,
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

fn paddle_page(text: &str, image: Option<(&str, &str)>) -> Value {
    let images = image.map_or(json!({}), |(name, url)| json!({ name: url }));
    json!({"page_index":0,"page_size":[600,800],"prunedResult":{"parsing_res_list":[{"block_id":0,"block_label":"text","block_content":text,"block_bbox":[1,2,300,40]}]},"markdown":{"text":text,"images":images}})
}

#[tokio::test]
async fn paddle_job_splits_long_pdf_into_page_ranges_and_keeps_every_range() {
    let root = tempdir().unwrap();
    let pdf = root.path().join("source.pdf");
    tokio::fs::write(&pdf, include_bytes!("fixtures/two_pages.pdf"))
        .await
        .unwrap();
    // 两个页段都从 page_index 0 起编号，且用了同名不同 URL 的图片。
    let (base, requests) = server(|base| {
        let line = |text: &str, url: String| {
            json!({"result":{"layoutParsingResults":[paddle_page(&format!("{text} <img src=\"imgs/a.jpg\">"), Some(("imgs/a.jpg", &url)))]}}).to_string().into_bytes()
        };
        vec![
            json!({"code":0,"data":{"jobId":"first"}}).to_string().into_bytes(),
            json!({"code":0,"data":{"jobId":"second"}}).to_string().into_bytes(),
            json!({"code":0,"data":{"state":"done","resultUrl":{"jsonUrl":format!("{base}/first.jsonl")}}}).to_string().into_bytes(),
            line("Head", format!("{base}/head.jpg")),
            json!({"code":0,"data":{"state":"done","resultUrl":{"jsonUrl":format!("{base}/second.jsonl")}}}).to_string().into_bytes(),
            line("Tail", format!("{base}/tail.jpg")),
            b"head image".to_vec(),
            b"tail image".to_vec(),
        ]
    })
    .await;
    let mut client = OcrClient::new(network::client(Some(""), false).unwrap());
    client.poll_interval = Duration::from_millis(1);
    let output = client
        .paddle_job(
            &pdf,
            &format!("{base}/jobs"),
            "key",
            &PaddleOptions::default(),
            Some(1500),
            &CancellationToken::new(),
            |_| {},
        )
        .await
        .unwrap();
    let pages: Vec<_> = output
        .structure
        .pages
        .iter()
        .map(|p| p.page_index)
        .collect();
    assert_eq!(pages, [0, 1]);
    assert!(output.raw_markdown.starts_with("Head"));
    assert!(
        output
            .raw_markdown
            .contains("Tail <img src=\"p1_imgs/a.jpg\">")
    );
    assert_eq!(output.assets["imgs/a.jpg"], b"head image");
    assert_eq!(output.assets["p1_imgs/a.jpg"], b"tail image");
    let requests = requests.await.unwrap();
    let first = String::from_utf8_lossy(&requests[0].body);
    let second = String::from_utf8_lossy(&requests[1].body);
    assert!(first.contains("1-1000") && second.contains("1001-1500"));
    assert!(first.contains("name=\"batchId\"\r\n\r\nnr_"));
}

#[test]
fn page_plan_splits_only_above_the_provider_limit() {
    use ocr::chunks::{PageChunk, plan};
    assert_eq!(
        plan(Some(200), 200),
        [PageChunk {
            index: 0,
            start: 1,
            end: 200,
            whole: true
        }]
    );
    assert_eq!(plan(None, 200)[0].ranges(), None);
    let ranges: Vec<_> = plan(Some(720), 200)
        .iter()
        .map(|c| c.ranges().unwrap())
        .collect();
    assert_eq!(ranges, ["1-200", "201-400", "401-600", "601-720"]);
}

#[test]
fn paddle_structure_uses_list_order_when_page_index_restarts() {
    let raw = json!({"layoutParsingResults":[paddle_page("A", None), paddle_page("B", None)]});
    let structure = otter_core::document::structure::Structure::from_value(&raw).unwrap();
    let pages: Vec<_> = structure.pages.iter().map(|p| p.page_index).collect();
    assert_eq!(pages, [0, 1]);
}

fn mineru_range(text: &str, image: &[u8], page_idx: u64) -> Vec<u8> {
    let layout = json!({"_backend":"vlm","pdf_info":[{"page_idx":page_idx,"page_size":[600,800],"para_blocks":[{"type":"text","bbox":[10,10,200,40],"lines":[{"bbox":[10,10,200,40],"spans":[{"type":"text","content":text}]}]},{"type":"image","bbox":[10,50,200,200],"blocks":[{"type":"image_body","bbox":[10,50,200,200],"lines":[{"bbox":[10,50,200,200],"spans":[{"type":"image","image_path":"fig.jpg"}]}]}]}],"discarded_blocks":[]}]}).to_string();
    let markdown = format!("{text}\n\n![](images/fig.jpg)");
    zip(&[
        ("full.md", markdown.as_bytes()),
        ("layout.json", layout.as_bytes()),
        ("images/fig.jpg", image),
    ])
}

#[test]
fn mineru_ranges_merge_in_page_order_with_global_indices_and_distinct_images() {
    use ocr::chunks::plan;
    let chunks = plan(Some(250), 200);
    // 交给合并的顺序与页段顺序相反，每段的 page_idx 都从 0 起。
    let merged = ocr::chunks::merge_mineru_zips(vec![
        (chunks[1], mineru_range("Tail", b"tail", 0)),
        (chunks[0], mineru_range("Head", b"head", 0)),
    ])
    .unwrap();
    let output = ocr::mineru_package(&merged, &[]).unwrap();
    assert!(output.raw_markdown.starts_with("Head"));
    assert!(
        output
            .raw_markdown
            .contains("Tail\n\n![](images/c1_fig.jpg)")
    );
    let pages: Vec<_> = output
        .structure
        .pages
        .iter()
        .map(|p| p.page_index)
        .collect();
    assert_eq!(pages, [0, 200]);
    assert_eq!(output.assets["images/fig.jpg"], b"head");
    assert_eq!(output.assets["images/c1_fig.jpg"], b"tail");
    let paths: Vec<_> = output.raw["pdf_info"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p.to_string().contains("c1_fig.jpg"))
        .collect();
    assert_eq!(paths, [false, true]);
}

#[test]
fn mineru_merge_refuses_a_range_without_markdown() {
    let chunks = ocr::chunks::plan(Some(250), 200);
    let error = ocr::chunks::merge_mineru_zips(vec![
        (chunks[0], mineru_range("Head", b"head", 0)),
        (chunks[1], zip(&[("images/x.jpg", b"x")])),
    ])
    .unwrap_err();
    assert_eq!(error.code, ErrorCode::InvalidData);
}

#[tokio::test]
async fn mineru_document_uploads_each_page_range_and_waits_for_all() {
    let root = tempdir().unwrap();
    let pdf = root.path().join("source.pdf");
    tokio::fs::write(&pdf, b"%PDF-1.7\nlong").await.unwrap();
    let (base, requests) = server(|base| vec![
        json!({"code":0,"data":{"batch_id":"b","file_urls":[format!("{base}/u0"),format!("{base}/u1")]}}).to_string().into_bytes(),
        vec![], vec![],
        json!({"code":0,"data":{"extract_result":[{"data_id":"doc_c1","state":"done","full_zip_url":format!("{base}/z1")},{"data_id":"doc_c0","state":"running"}]}}).to_string().into_bytes(),
        mineru_range("Tail", b"tail", 0),
        json!({"code":0,"data":{"extract_result":[{"data_id":"doc_c0","state":"done","full_zip_url":format!("{base}/z0")}]}}).to_string().into_bytes(),
        mineru_range("Head", b"head", 0),
    ]).await;
    let mut client = OcrClient::new(network::client(None, false).unwrap());
    client.poll_interval = Duration::from_millis(1);
    let output = client
        .mineru_document(
            &base,
            "k",
            "doc",
            &pdf,
            Some(250),
            &MineruOptions::default(),
            &CancellationToken::new(),
            |_| {},
        )
        .await
        .unwrap();
    assert!(output.raw_markdown.starts_with("Head"));
    let requests = requests.await.unwrap();
    let body: Value = serde_json::from_slice(&requests[0].body).unwrap();
    assert_eq!(body["files"][0]["page_ranges"], "1-200");
    assert_eq!(body["files"][1]["page_ranges"], "201-250");
    assert_eq!(body["files"][1]["data_id"], "doc_c1");
}
