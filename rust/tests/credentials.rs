use otter_core::{
    credentials::{CredentialInput, Credentials},
    error::ErrorCode,
    storage::Storage,
};
use serde_json::json;
use tempfile::tempdir;

#[test]
fn vault_keys_stay_in_memory_and_cannot_be_written_as_settings() {
    let root = tempdir().unwrap();
    let storage = Storage::open(root.path()).unwrap();
    let credentials = Credentials::default();
    for key in [
        "agent_api_key_instance",
        "doc_extract_api_key_mineru",
        "zotero_api_key",
        "backup_webdav_password",
        "backup_s3_secret_access_key",
    ] {
        assert_eq!(
            storage
                .put_setting(key, &json!("private-test-value"))
                .unwrap_err()
                .code,
            ErrorCode::InvalidArgument
        );
        assert!(storage.setting(key).unwrap().is_none());
        credentials
            .inject(vec![CredentialInput {
                key: key.into(),
                value: "private-test-value".into(),
            }])
            .unwrap();
        assert_eq!(credentials.get(key).unwrap(), "private-test-value");
    }
    credentials
        .inject(vec![CredentialInput {
            key: "zotero_api_key".into(),
            value: String::new(),
        }])
        .unwrap();
    assert_eq!(
        credentials.get("zotero_api_key").unwrap_err().code,
        ErrorCode::Authentication
    );
    credentials.clear().unwrap();
    assert_eq!(
        credentials.get("agent_api_key_instance").unwrap_err().code,
        ErrorCode::Authentication
    );
    drop(storage);
    let reopened = Storage::open(root.path()).unwrap();
    assert!(
        reopened
            .setting("agent_api_key_instance")
            .unwrap()
            .is_none()
    );
}

#[test]
fn credentials_persist_privately_and_survive_a_corrupt_file() {
    let root = tempdir().unwrap();
    let path = root.path().join("credentials.json");
    let credentials = Credentials::open(path.clone()).unwrap();
    credentials
        .inject(vec![
            CredentialInput {
                key: "zotero_api_key".into(),
                value: "zotero-secret".into(),
            },
            CredentialInput {
                key: "agent_api_key_main".into(),
                value: "agent-secret".into(),
            },
        ])
        .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(&path).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600);
    }
    let unknown = credentials.inject(vec![CredentialInput {
        key: "not_a_credential".into(),
        value: "x".into(),
    }]);
    assert_eq!(unknown.unwrap_err().code, ErrorCode::InvalidArgument);

    let reopened = Credentials::open(path.clone()).unwrap();
    let keys: Vec<_> = reopened
        .entries()
        .unwrap()
        .into_iter()
        .map(|e| (e.key, e.value))
        .collect();
    assert_eq!(
        keys,
        [
            ("agent_api_key_main".to_owned(), "agent-secret".to_owned()),
            ("zotero_api_key".to_owned(), "zotero-secret".to_owned()),
        ]
    );
    reopened
        .inject(vec![CredentialInput {
            key: "zotero_api_key".into(),
            value: String::new(),
        }])
        .unwrap();
    assert!(
        Credentials::open(path.clone())
            .unwrap()
            .optional("zotero_api_key")
            .unwrap()
            .is_none()
    );

    std::fs::write(&path, b"{not json").unwrap();
    let recovered = Credentials::open(path.clone()).unwrap();
    assert!(recovered.entries().unwrap().is_empty());
    assert!(root.path().join("credentials.json.invalid").is_file());
    assert!(!path.exists());
}
