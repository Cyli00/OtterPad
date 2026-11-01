mod support;

use otter_core::{
    ai::{
        AiClient,
        catalog::ModelCapabilities,
        chat::{CHAT_SYSTEM, ChatMessage, ChatSession, ChatStore},
        types::*,
    },
    error::ErrorCode,
};
use serde_json::{Value, json};
use support::{Reply, server};
use tempfile::tempdir;
use tokio_util::sync::CancellationToken;

fn model(base_url: String) -> ModelConfig {
    ModelConfig {
        provider: Provider::OpenaiCompatible,
        base_url,
        model: "chat-model".into(),
        params: ModelParams::default(),
        thinking_spec: None,
        capabilities: Some(ModelCapabilities {
            image_input: true,
            ..Default::default()
        }),
    }
}

#[test]
fn actual_v017_serialized_chat_roundtrips_anchors_activities_and_rejects_stale_saves() {
    let root = tempdir().unwrap();
    let directory = root.path().join("library/paper/chats");
    std::fs::create_dir_all(&directory).unwrap();
    let raw = include_bytes!("fixtures/chat-v017.json");
    std::fs::write(directory.join("legacy-session.json"), raw).unwrap();
    std::fs::write(directory.join("broken.json"), b"{").unwrap();
    let store = ChatStore::new(root.path().into());
    let session = store.load("paper", "legacy-session").unwrap();
    let expected: Value = serde_json::from_slice(raw).unwrap();
    let serialized = serde_json::to_value(&session).unwrap();
    assert_eq!(serialized, expected);
    let list = store.list("paper").unwrap();
    assert_eq!(list.sessions.len(), 1);
    assert_eq!(list.unreadable, ["broken"]);
    let mut renamed = session.clone();
    renamed.title = "Updated title".into();
    let next = store
        .save("paper", &renamed, Some(&session.revision))
        .unwrap();
    assert_ne!(session.revision, next.revision);
    assert_eq!(
        store
            .save("paper", &session, Some(&session.revision))
            .unwrap_err()
            .code,
        ErrorCode::Conflict
    );
    assert_eq!(
        store.load("paper", "legacy-session").unwrap().messages[0].quote_anchor,
        session.messages[0].quote_anchor
    );
}

#[tokio::test]
async fn chat_keeps_document_context_and_first_turn_images_across_history() {
    let root = tempdir().unwrap();
    let directory = root.path().join("library/paper");
    std::fs::create_dir_all(directory.join("figures")).unwrap();
    std::fs::write(
        directory.join("extract.raw.md"),
        "# Actual document\n\nPaper findings.",
    )
    .unwrap();
    std::fs::write(directory.join("figures/f1.png"), b"figure image").unwrap();
    std::fs::write(
        directory.join("figures/figures.json"),
        serde_json::to_vec(
            &json!([{"imagePath":"f1.png","captionText":"Figure 1: measured result"}]),
        )
        .unwrap(),
    )
    .unwrap();
    let store = ChatStore::new(root.path().into());
    let session = store
        .save("paper", &ChatSession::create("Paper".into()).unwrap(), None)
        .unwrap();
    let (base, handle) = server(2, |index, request| {
        assert!(request.head.starts_with("POST /v1/chat/completions "));
        let body: Value = serde_json::from_slice(&request.body).unwrap();
        assert!(
            body["messages"][0]["content"]
                .as_str()
                .unwrap()
                .contains("Paper findings.")
        );
        assert_eq!(
            body["messages"][1]["content"][0]["text"],
            "Figure 1: measured result"
        );
        if index == 0 {
            assert_eq!(
                body["messages"][1]["content"][2]["text"],
                "> selected evidence\n\nQuestion one"
            );
        } else {
            assert_eq!(body["messages"].as_array().unwrap().len(), 4);
            assert_eq!(body["messages"][2]["role"], "assistant");
            assert_eq!(body["messages"][3]["content"], "Follow up");
        }
        Reply::json(
            json!({"choices":[{"message":{"content":"Grounded answer"},"finish_reason":"stop"}]}),
        )
    })
    .await;
    let ai = AiClient::new(None, false).unwrap();
    let config = model(base);
    let token = CancellationToken::new();
    let mut question = ChatMessage::user("Question one".into()).unwrap();
    question.quoted_text = Some("selected evidence".into());
    let answered = store
        .ask(
            "paper",
            &session.id,
            question,
            CHAT_SYSTEM,
            &config,
            "key",
            false,
            false,
            false,
            &ai,
            None,
            &token,
            |_| Ok(()),
        )
        .await
        .unwrap();
    assert_eq!(answered.messages.len(), 2);
    let followed = store
        .ask(
            "paper",
            &session.id,
            ChatMessage::user("Follow up".into()).unwrap(),
            CHAT_SYSTEM,
            &config,
            "key",
            false,
            false,
            false,
            &ai,
            None,
            &token,
            |_| Ok(()),
        )
        .await
        .unwrap();
    assert_eq!(followed.messages.len(), 4);
    assert_eq!(handle.await.unwrap().len(), 2);
}

#[tokio::test]
async fn deleting_session_during_generation_cannot_resurrect_it() {
    let root = tempdir().unwrap();
    let directory = root.path().join("library/paper");
    std::fs::create_dir_all(&directory).unwrap();
    std::fs::write(directory.join("extract.raw.md"), "Paper.").unwrap();
    let store = ChatStore::new(root.path().into());
    let session = store
        .save("paper", &ChatSession::create("Paper".into()).unwrap(), None)
        .unwrap();
    let (base,handle)=server(1,|_,_|Reply::sse("data: {\"choices\":[{\"delta\":{\"content\":\"Answer\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")).await;
    let error = store
        .ask(
            "paper",
            &session.id,
            ChatMessage::user("Question".into()).unwrap(),
            CHAT_SYSTEM,
            &model(base),
            "key",
            false,
            false,
            true,
            &AiClient::new(None, false).unwrap(),
            None,
            &CancellationToken::new(),
            |event| {
                if matches!(event, ChatEvent::TextDelta { .. }) {
                    store.delete("paper", &session.id)?;
                }
                Ok(())
            },
        )
        .await
        .unwrap_err();
    assert_eq!(error.code, ErrorCode::Conflict);
    assert!(store.list("paper").unwrap().sessions.is_empty());
    handle.await.unwrap();
}
