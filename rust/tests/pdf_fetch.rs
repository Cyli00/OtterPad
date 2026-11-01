mod support;
use otter_core::{
    error::ErrorCode,
    library::fetch::{PdfEndpoints, PdfFetcher, PdfSource, citation_pdf_url, publisher_pdf_url},
    network,
};
use serde_json::json;
use support::Reply;
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn endpoints(base: &str) -> PdfEndpoints {
    PdfEndpoints {
        doi: format!("{base}/doi/"),
        unpaywall: format!("{base}/oa/"),
        pubmed: format!("{base}/summary"),
        pmc: format!("{base}/articles/"),
    }
}
fn pdf() -> Reply {
    Reply {
        mime: "application/pdf",
        body: include_bytes!("fixtures/two_pages.pdf").to_vec(),
        ..Reply::json(json!(null))
    }
}
fn host(head: &str) -> &str {
    head.lines()
        .find_map(|line| line.strip_prefix("host: "))
        .unwrap()
}

#[tokio::test]
async fn publisher_html_resolves_entities_sends_referer_and_downloads_real_pdf() {
    let (base, server) = support::server(2, |index, request| {
        assert!(request.body.is_empty());
        if index == 0 {
            assert!(request.head.starts_with("GET /doi/10.1234%2Fpaper "));
            assert!(
                request
                    .head
                    .to_lowercase()
                    .contains("user-agent: mozilla/5.0")
            );
            Reply {
                mime: "text/html",
                body:
                    br#"<META CONTENT='/download?token=one&amp;part=two' NAME='CITATION_PDF_URL'>"#
                        .to_vec(),
                ..Reply::json(json!(null))
            }
        } else {
            assert!(
                request
                    .head
                    .starts_with("GET /download?token=one&part=two ")
            );
            assert!(
                request
                    .head
                    .to_lowercase()
                    .contains("referer: http://127.0.0.1:")
            );
            pdf()
        }
    })
    .await;
    let mut fetcher = PdfFetcher::new(network::client(Some(""), true).unwrap());
    fetcher.endpoints = endpoints(&base);
    let root = tempdir().unwrap();
    let path = root.path().join("download.pdf");
    let report = fetcher
        .fetch_doi("10.1234/paper", &path, &CancellationToken::new(), None)
        .await
        .unwrap();
    assert!(matches!(report.source, PdfSource::Citation));
    assert_eq!(
        std::fs::read(path).unwrap(),
        include_bytes!("fixtures/two_pages.pdf")
    );
    server.await.unwrap();
}

#[tokio::test]
async fn invalid_publisher_payload_falls_back_to_open_access_and_failure_keeps_previous_pdf() {
    let (base,server)=support::server(7,|index,request| {
        match index {
            0|4=>Reply{mime:"text/html",body:br#"<meta name='citation_pdf_url' content='/blocked'>"#.to_vec(),..Reply::json(json!(null))},
            1|5=>Reply{mime:"text/html",body:b"<html>Sign in</html>".to_vec(),..Reply::json(json!(null))},
            2=>{assert!(request.head.contains("GET /oa/10.1234%2Fpaper?email="));Reply::json(json!({"best_oa_location":{"url_for_pdf":format!("http://{}/open.pdf",host(&request.head))}}))},
            3=>{assert!(request.head.starts_with("GET /open.pdf "));pdf()},
            _=>Reply::json(json!({"best_oa_location":null})),
        }
    }).await;
    let mut fetcher = PdfFetcher::new(network::client(Some(""), true).unwrap());
    fetcher.endpoints = endpoints(&base);
    let root = tempdir().unwrap();
    let path = root.path().join("source.pdf");
    let token = CancellationToken::new();
    let report = fetcher
        .fetch_doi("10.1234/paper", &path, &token, None)
        .await
        .unwrap();
    assert!(matches!(report.source, PdfSource::Unpaywall));
    assert!(report.warnings.contains(&ErrorCode::InvalidData));
    let previous = std::fs::read(&path).unwrap();
    assert_eq!(
        fetcher
            .fetch_doi("10.1234/paper", &path, &token, None)
            .await
            .unwrap_err()
            .code,
        ErrorCode::NotFound
    );
    assert_eq!(std::fs::read(&path).unwrap(), previous);
    assert!(
        root.path()
            .read_dir()
            .unwrap()
            .all(|entry| entry.unwrap().file_name() == "source.pdf")
    );
    server.await.unwrap();
}

#[tokio::test]
async fn pubmed_uses_pmc_identifier_and_streams_europe_pmc_pdf() {
    let (base, server) = support::server(2, |index, request| {
        if index == 0 {
            assert!(
                request
                    .head
                    .contains("GET /summary?db=pubmed&id=123&retmode=json")
            );
            Reply::json(
                json!({"result":{"123":{"articleids":[{"idtype":"pmc","value":"PMC456"}]}}}),
            )
        } else {
            assert!(request.head.starts_with("GET /articles/PMC456?pdf=render "));
            pdf()
        }
    })
    .await;
    let mut fetcher = PdfFetcher::new(network::client(Some(""), true).unwrap());
    fetcher.endpoints = endpoints(&base);
    let root = tempdir().unwrap();
    let path = root.path().join("source.pdf");
    let report = fetcher
        .fetch_pmid("123", &path, &CancellationToken::new(), None)
        .await
        .unwrap();
    assert!(matches!(report.source, PdfSource::EuropePmc));
    assert_eq!(
        std::fs::read(path).unwrap(),
        include_bytes!("fixtures/two_pages.pdf")
    );
    server.await.unwrap();
}

#[test]
fn publisher_fallbacks_use_exact_domain_boundaries_and_safe_html_schemes() {
    let cases = [
        (
            "https://arxiv.org/abs/1706.03762",
            "https://arxiv.org/pdf/1706.03762",
        ),
        (
            "https://www.biorxiv.org/content/10.1101/123v1/",
            "https://www.biorxiv.org/content/10.1101/123v1.full.pdf",
        ),
        (
            "https://link.springer.com/article/test",
            "https://link.springer.com/content/pdf/10.1234/paper.pdf",
        ),
        (
            "https://www.nature.com/articles/paper",
            "https://www.nature.com/articles/paper.pdf",
        ),
        (
            "https://onlinelibrary.wiley.com/doi/abs/test",
            "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1234/paper?download=true",
        ),
        (
            "https://www.sciencedirect.com/science/article/pii/test?x=1",
            "https://www.sciencedirect.com/science/article/pii/test/pdfft?download=true",
        ),
        (
            "https://pubs.acs.org/doi/abs/test",
            "https://pubs.acs.org/doi/pdf/10.1234/paper",
        ),
        (
            "https://www.tandfonline.com/doi/abs/test",
            "https://www.tandfonline.com/doi/pdf/10.1234/paper",
        ),
        (
            "https://pubs.rsc.org/en/content/articlelanding/2025/test",
            "https://pubs.rsc.org/en/content/articlepdf/2025/test",
        ),
        (
            "https://www.mdpi.com/123/456/",
            "https://www.mdpi.com/123/456/pdf",
        ),
    ];
    for (landing, expected) in cases {
        assert_eq!(
            publisher_pdf_url(&reqwest::Url::parse(landing).unwrap(), "10.1234/paper")
                .unwrap()
                .as_str(),
            expected
        );
    }
    assert!(
        publisher_pdf_url(
            &reqwest::Url::parse("https://arxiv.org.attacker.example/abs/123").unwrap(),
            "10.1234/paper"
        )
        .is_none()
    );
    let base = reqwest::Url::parse("https://publisher.example/paper").unwrap();
    assert!(
        citation_pdf_url(
            "<meta name='citation_pdf_url' content='file:///etc/passwd'>",
            &base
        )
        .is_none()
    );
}
