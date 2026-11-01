mod support;

use otter_core::{
    error::ErrorCode,
    network::{TransferObserver, TransferProgress},
    sync::remote::{BackupRemote, RemoteConfig},
};
use std::sync::{Arc, Mutex};
use support::{Reply, server};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

#[tokio::test]
async fn webdav_creates_collections_streams_files_and_filters_multistatus_entries() {
    let payload: Vec<u8> = (0..300_000).map(|i| (i % 251) as u8).collect();
    let expected = payload.clone();
    let (base,handle)=server(7,move|index,request| {
        assert!(request.head.to_lowercase().contains("authorization: basic dXNlcjpwYXNz".to_lowercase().as_str()));
        match index {
            0=>{assert!(request.head.starts_with("OPTIONS /dav/ "));Reply::json(serde_json::json!({}))},
            1=>{assert!(request.head.starts_with("MKCOL /dav/folder "));Reply{status:405,..Reply::json(serde_json::Value::Null)}},
            2=>{assert!(request.head.starts_with("MKCOL /dav/folder/sub "));Reply{status:201,..Reply::json(serde_json::Value::Null)}},
            3=>{assert!(request.head.starts_with("PUT /dav/folder/sub/%E5%A4%87%E4%BB%BD%20one.zip "));assert_eq!(request.body,expected);Reply{status:201,..Reply::json(serde_json::Value::Null)}},
            4=>{assert!(request.head.starts_with("PROPFIND /dav/folder/sub/ "));assert!(request.head.to_lowercase().contains("depth: 1"));Reply{status:207,mime:"application/xml",headers:Vec::new(),body:br#"<d:multistatus xmlns:d="DAV:">
<d:response><d:href>/dav/folder/sub/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
<d:response><d:href>/dav/folder/sub/%E5%A4%87%E4%BB%BD%20one.zip</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>300000</d:getcontentlength><d:getlastmodified>Sun, 06 Nov 1994 08:49:37 GMT</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
<d:response><d:href>/dav/folder/sub/nested/child.zip</d:href><d:propstat><d:prop/><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
<d:response><d:href>/dav/folder/sub/unavailable.zip</d:href><d:propstat><d:prop/><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>
</d:multistatus>"#.to_vec()}},
            5=>{assert!(request.head.starts_with("GET /dav/folder/sub/%E5%A4%87%E4%BB%BD%20one.zip "));Reply{status:200,mime:"application/zip",body:expected.clone(),headers:Vec::new()}},
            _=>{assert!(request.head.starts_with("DELETE /dav/folder/sub/%E5%A4%87%E4%BB%BD%20one.zip "));Reply{status:204,mime:"text/plain",body:Vec::new(),headers:Vec::new()}},
        }
    }).await;
    let remote = BackupRemote::new(
        RemoteConfig::Webdav {
            server_url: format!("{base}/dav/"),
            username: "user".into(),
            remote_dir: "/folder/sub/".into(),
            file_name: "fixed.zip".into(),
        },
        "pass".into(),
        None,
        false,
    )
    .unwrap();
    let root = tempdir().unwrap();
    let source = root.path().join("source.zip");
    std::fs::write(&source, &payload).unwrap();
    let token = CancellationToken::new();
    let progress = Arc::new(Mutex::new(Vec::<TransferProgress>::new()));
    let captured = progress.clone();
    let observer: TransferObserver = Arc::new(move |event| captured.lock().unwrap().push(event));
    remote.ping(&token).await.unwrap();
    remote
        .upload(&source, "备份 one.zip", &token, Some(observer.clone()))
        .await
        .unwrap();
    let entries = remote.list(&token).await.unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].name, "备份 one.zip");
    assert_eq!(entries[0].size, 300_000);
    assert_eq!(entries[0].modified_at, Some(784111777000));
    let target = root.path().join("download.zip");
    std::fs::write(&target, b"old").unwrap();
    remote
        .download("备份 one.zip", &target, 1_000_000, &token, Some(&observer))
        .await
        .unwrap();
    assert_eq!(std::fs::read(target).unwrap(), payload);
    remote.delete("备份 one.zip", &token).await.unwrap();
    assert_eq!(
        progress.lock().unwrap().last().unwrap().transferred,
        300_000
    );
    assert_eq!(handle.await.unwrap().len(), 7);
}

#[tokio::test]
async fn s3_signs_streamed_payload_and_encodes_sorted_paginated_queries() {
    let payload = b"archive body with binary \0\xff".to_vec();
    let expected = payload.clone();
    let (base,handle)=server(6,move|index,request| {
        let head=request.head.to_lowercase();assert!(head.contains("authorization: aws4-hmac-sha256 credential=local-access/"));assert!(head.contains("signedheaders=host;x-amz-content-sha256;x-amz-date"));assert!(!head.contains("secret-for-local-test"));
        match index {
            0=>{assert!(request.head.starts_with("HEAD /gateway/bucket "));Reply{status:200,mime:"text/plain",body:Vec::new(),headers:Vec::new()}},
            1=>{assert!(request.head.starts_with("PUT /gateway/bucket/archive%20space/%E5%A4%87%E4%BB%BD%20one.zip "));assert_eq!(request.body,expected);Reply::json(serde_json::Value::Null)},
            2=>{assert!(request.head.starts_with("GET /gateway/bucket?list-type=2&prefix=archive%20space%2F "));Reply{status:200,mime:"application/xml",headers:Vec::new(),body:br#"<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><IsTruncated>true</IsTruncated><NextContinuationToken>ab+c/=</NextContinuationToken><Contents><Key>archive space/one.zip</Key><Size>27</Size><LastModified>2025-01-01T00:00:00Z</LastModified></Contents><Contents><Key>archive space/nested/child.zip</Key><Size>1</Size></Contents></ListBucketResult>"#.to_vec()}},
            3=>{assert!(request.head.starts_with("GET /gateway/bucket?continuation-token=ab%2Bc%2F%3D&list-type=2&prefix=archive%20space%2F "));Reply{status:200,mime:"application/xml",headers:Vec::new(),body:br#"<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>archive space/two &amp; three.zip</Key><Size>9</Size></Contents></ListBucketResult>"#.to_vec()}},
            4=>Reply{status:200,mime:"application/zip",headers:Vec::new(),body:expected.clone()},
            _=>{assert!(request.head.starts_with("DELETE /gateway/bucket/archive%20space/%E5%A4%87%E4%BB%BD%20one.zip "));Reply{status:204,mime:"text/plain",headers:Vec::new(),body:Vec::new()}},
        }
    }).await;
    let remote = BackupRemote::new(
        RemoteConfig::S3 {
            endpoint: format!("{base}/gateway"),
            region: "test-region".into(),
            bucket: "bucket".into(),
            object_key: "archive space/fixed.zip".into(),
            path_style: true,
            access_key: "local-access".into(),
        },
        "secret-for-local-test".into(),
        None,
        false,
    )
    .unwrap();
    assert_eq!(remote.fixed_name(), "fixed.zip");
    let root = tempdir().unwrap();
    let source = root.path().join("source.zip");
    std::fs::write(&source, &payload).unwrap();
    let token = CancellationToken::new();
    remote.ping(&token).await.unwrap();
    remote
        .upload(&source, "备份 one.zip", &token, None)
        .await
        .unwrap();
    let entries = remote.list(&token).await.unwrap();
    assert_eq!(
        entries.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(),
        ["one.zip", "two & three.zip"]
    );
    let target = root.path().join("download.zip");
    remote
        .download("备份 one.zip", &target, 100, &token, None)
        .await
        .unwrap();
    assert_eq!(std::fs::read(target).unwrap(), payload);
    remote.delete("备份 one.zip", &token).await.unwrap();
    assert_eq!(handle.await.unwrap().len(), 6);
}

#[tokio::test]
async fn cancelled_download_preserves_previous_file_and_removes_temporary() {
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    };
    let root = tempdir().unwrap();
    let path = root.path().join("backup.zip");
    std::fs::write(&path, b"previous archive").unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let serving = tokio::spawn(async move {
        let (mut socket, _) = listener.accept().await.unwrap();
        support::read(&mut socket).await;
        socket
            .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 10000\r\n\r\npartial")
            .await
            .unwrap();
        let mut bytes = [0; 1];
        assert_eq!(
            tokio::time::timeout(std::time::Duration::from_secs(2), socket.read(&mut bytes))
                .await
                .unwrap()
                .unwrap(),
            0
        );
    });
    let remote = BackupRemote::new(
        RemoteConfig::Webdav {
            server_url: base,
            username: "user".into(),
            remote_dir: "".into(),
            file_name: "backup.zip".into(),
        },
        "pass".into(),
        None,
        false,
    )
    .unwrap();
    let token = CancellationToken::new();
    let cancel = token.clone();
    let observer: TransferObserver = Arc::new(move |progress| {
        if progress.transferred > 0 {
            cancel.cancel();
        }
    });
    assert_eq!(
        remote
            .download("backup.zip", &path, 10000, &token, Some(&observer))
            .await
            .unwrap_err()
            .code,
        ErrorCode::Cancelled
    );
    assert_eq!(std::fs::read(&path).unwrap(), b"previous archive");
    assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 1);
    serving.await.unwrap();
}
