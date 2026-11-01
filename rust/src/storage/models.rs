/// Persisted metadata. Timestamps use epoch milliseconds, including legacy data.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Document {
    pub id: String,
    pub title: String,
    pub authors: Vec<String>,
    pub journal: Option<String>,
    pub year: Option<String>,
    pub doi: Option<String>,
    pub keywords: Vec<String>,
    pub content_hash: Option<String>,
    pub added_at: i64,
}
