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
