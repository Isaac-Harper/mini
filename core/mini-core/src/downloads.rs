use std::path::{Path, PathBuf};

pub fn downloads_directory() -> PathBuf {
    let home = std::env::var_os("HOME").expect("HOME is not set");
    PathBuf::from(home).join("Downloads")
}

pub fn unique_destination(directory: &Path, suggested_name: &str) -> PathBuf {
    let file_name = Path::new(suggested_name)
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("download");
    let candidate = directory.join(file_name);
    if !candidate.exists() {
        return candidate;
    }
    let name_path = Path::new(file_name);
    let stem = name_path
        .file_stem()
        .and_then(|stem| stem.to_str())
        .expect("file name has a UTF-8 stem");
    let extension = name_path
        .extension()
        .and_then(|extension| extension.to_str());
    (1..)
        .map(|counter| match extension {
            Some(extension) => directory.join(format!("{stem} ({counter}).{extension}")),
            None => directory.join(format!("{stem} ({counter})")),
        })
        .find(|path| !path.exists())
        .expect("an unused download name exists")
}

#[cfg(test)]
mod tests {
    use super::unique_destination;
    use std::fs;

    #[test]
    fn appends_counter_before_extension_until_unused() {
        let directory = std::env::temp_dir().join(format!("mini-downloads-{}", std::process::id()));
        fs::create_dir_all(&directory).unwrap();
        assert_eq!(
            unique_destination(&directory, "report.pdf"),
            directory.join("report.pdf")
        );
        fs::write(directory.join("report.pdf"), b"").unwrap();
        fs::write(directory.join("report (1).pdf"), b"").unwrap();
        assert_eq!(
            unique_destination(&directory, "report.pdf"),
            directory.join("report (2).pdf")
        );
        fs::write(directory.join("notes"), b"").unwrap();
        assert_eq!(
            unique_destination(&directory, "notes"),
            directory.join("notes (1)")
        );
        assert_eq!(
            unique_destination(&directory, "../escape.txt"),
            directory.join("escape.txt")
        );
        fs::remove_dir_all(&directory).unwrap();
    }
}
