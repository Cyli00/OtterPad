use otter_core::document::{figures::find_figures, structure::Structure};
use serde_json::json;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("expected OCR JSON path")?;
    let structure = Structure::parse(&std::fs::read_to_string(path)?)?;
    let output:Vec<_>=find_figures(&structure).iter().map(|f|{
        let mut ids:Vec<_>=f.blocks.iter().map(|b|b.block_id.as_str()).collect();ids.sort();
        json!({"page_index":f.page_index,"caption_text":f.caption_text,"caption_name":f.caption_name,"block_ids":ids,"caption_refs":f.caption_refs})
    }).collect();
    println!("{}", serde_json::to_string(&output)?);
    Ok(())
}
