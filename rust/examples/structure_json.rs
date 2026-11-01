use otter_core::document::structure::Structure;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("expected OCR JSON path")?;
    let structure = Structure::parse(&std::fs::read_to_string(path)?)?;
    println!("{}", structure.legacy_json(None));
    Ok(())
}
