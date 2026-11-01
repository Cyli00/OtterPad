use otter_core::{
    error::ErrorCode,
    runtime::{Runtime, RuntimeConfig},
    storage::Storage,
    tasks::Tasks,
};
use serde_json::json;
use std::sync::Arc;
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

#[tokio::test]
async fn runtime_recovers_before_opening_storage_and_logs_only_operation_codes() {
    let root = tempdir().unwrap();
    let live = Storage::open(root.path()).unwrap();
    live.put_setting("theme_mode", &json!("old")).unwrap();
    drop(live);
    let stage = root.path().join(".restore-runtime");
    let replacement = Storage::open(&stage).unwrap();
    replacement
        .put_setting("theme_mode", &json!("uncommitted"))
        .unwrap();
    drop(replacement);
    std::fs::rename(
        root.path().join("v2"),
        root.path().join(".restore-runtime.previous"),
    )
    .unwrap();
    std::fs::rename(stage.join("v2"), root.path().join("v2")).unwrap();
    std::fs::write(root.path().join(".restore-pending.json"),json!({"stage":".restore-runtime","previous":".restore-runtime.previous","committed":false}).to_string()).unwrap();
    let config = RuntimeConfig {
        root: root.path().to_owned(),
        pdfium_library: None,
        bitmap_cache_bytes: 1024,
    };
    let tasks = Arc::new(Tasks::default());
    let token = CancellationToken::new();
    let (runtime, startup) = Runtime::open(config.clone(), tasks.clone(), token.clone(), |_| {})
        .await
        .unwrap();
    assert!(startup.migration.is_none());
    assert_eq!(
        runtime
            .with_storage(&token, "read_setting", |s| s.setting("theme_mode"))
            .await
            .unwrap(),
        Some(json!("old"))
    );
    assert!(!root.path().join(".restore-pending.json").exists());
    let secret = "never-written-runtime-credential-419";
    let error = runtime
        .with_storage(&token, "put_setting", move |s| {
            s.put_setting("zotero_api_key", &json!(secret))
        })
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::InvalidArgument);
    let logs = std::fs::read_dir(runtime.directory.join("logs"))
        .unwrap()
        .map(|e| std::fs::read_to_string(e.unwrap().path()).unwrap())
        .collect::<String>();
    assert!(logs.contains("put_setting InvalidArgument"));
    assert!(!logs.contains(secret));
    assert_eq!(
        Runtime::open(config, tasks, token, |_| {})
            .await
            .err()
            .unwrap()
            .code,
        ErrorCode::Conflict
    );
}
