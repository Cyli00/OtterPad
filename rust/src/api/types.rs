use crate::{
    error::{ErrorCode, OtterError, Result},
    library::Highlight,
};
use serde_json::Value;

/// JSON is confined to genuinely extensible setting and legacy-anchor values.
/// Business operations have separate typed APIs, never a route/JSON dispatcher.
pub enum JsonData {
    Null,
    Bool { value: bool },
    Integer { value: i64 },
    Unsigned { value: u64 },
    Number { value: f64 },
    String { value: String },
    Array { values: Vec<JsonData> },
    Object { entries: Vec<JsonEntry> },
}
pub struct JsonEntry {
    pub key: String,
    pub value: JsonData,
}
impl JsonData {
    pub(crate) fn into_value(self) -> Result<Value> {
        Ok(match self {
            Self::Null => Value::Null,
            Self::Bool { value } => value.into(),
            Self::Integer { value } => value.into(),
            Self::Unsigned { value } => value.into(),
            Self::Number { value } => serde_json::Number::from_f64(value)
                .map(Value::Number)
                .ok_or_else(|| {
                    OtterError::new(ErrorCode::InvalidArgument, "nonfinite JSON number")
                })?,
            Self::String { value } => value.into(),
            Self::Array { values } => Value::Array(
                values
                    .into_iter()
                    .map(Self::into_value)
                    .collect::<Result<_>>()?,
            ),
            Self::Object { entries } => {
                let mut values = serde_json::Map::new();
                for entry in entries {
                    if values
                        .insert(entry.key, entry.value.into_value()?)
                        .is_some()
                    {
                        return Err(OtterError::new(
                            ErrorCode::InvalidArgument,
                            "duplicate JSON key",
                        ));
                    }
                }
                Value::Object(values)
            }
        })
    }
    pub(crate) fn from_value(value: Value) -> Self {
        match value {
            Value::Null => Self::Null,
            Value::Bool(value) => Self::Bool { value },
            Value::String(value) => Self::String { value },
            Value::Number(value) => {
                if let Some(value) = value.as_i64() {
                    Self::Integer { value }
                } else if let Some(value) = value.as_u64() {
                    Self::Unsigned { value }
                } else {
                    Self::Number {
                        value: value.as_f64().expect("JSON number"),
                    }
                }
            }
            Value::Array(values) => Self::Array {
                values: values.into_iter().map(Self::from_value).collect(),
            },
            Value::Object(values) => Self::Object {
                entries: values
                    .into_iter()
                    .map(|(key, value)| JsonEntry {
                        key,
                        value: Self::from_value(value),
                    })
                    .collect(),
            },
        }
    }
}
pub struct Note {
    pub id: String,
    pub document_id: String,
    pub content: String,
    pub note: Option<String>,
    pub color: String,
    pub group_id: Option<String>,
    pub anchor: Option<JsonData>,
    pub created_at: i64,
}
impl Note {
    pub(crate) fn from_highlight(note: Highlight) -> Self {
        Self {
            id: note.id,
            document_id: note.document_id,
            content: note.content,
            note: note.note,
            color: note.color,
            group_id: note.group_id,
            anchor: note.anchor.map(JsonData::from_value),
            created_at: note.created_at,
        }
    }
    pub(crate) fn into_highlight(self) -> Result<Highlight> {
        Ok(Highlight {
            id: self.id,
            document_id: self.document_id,
            content: self.content,
            note: self.note,
            color: self.color,
            group_id: self.group_id,
            anchor: self.anchor.map(JsonData::into_value).transpose()?,
            created_at: self.created_at,
        })
    }
}
