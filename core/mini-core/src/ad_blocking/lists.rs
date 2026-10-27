use adblock::{Engine, FilterSet, lists::ParseOptions, resources::PermissionMask};
use std::{
    fs,
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};

use super::resources::{TRUSTED_PERMISSION, parse_resource_bundle};

pub struct FilterList {
    pub file_name: &'static str,
    pub url: &'static str,
    pub trusted: bool,
}

pub const FILTER_LISTS: [FilterList; 8] = [
    FilterList {
        file_name: "easylist.txt",
        url: "https://easylist.to/easylist/easylist.txt",
        trusted: false,
    },
    FilterList {
        file_name: "easyprivacy.txt",
        url: "https://easylist.to/easylist/easyprivacy.txt",
        trusted: false,
    },
    FilterList {
        file_name: "ublock-filters.txt",
        url: "https://ublockorigin.github.io/uAssets/filters/filters.min.txt",
        trusted: true,
    },
    FilterList {
        file_name: "ublock-badware.txt",
        url: "https://ublockorigin.github.io/uAssets/filters/badware.min.txt",
        trusted: true,
    },
    FilterList {
        file_name: "ublock-privacy.txt",
        url: "https://ublockorigin.github.io/uAssets/filters/privacy.min.txt",
        trusted: true,
    },
    FilterList {
        file_name: "ublock-quick-fixes.txt",
        url: "https://ublockorigin.github.io/uAssets/filters/quick-fixes.min.txt",
        trusted: true,
    },
    FilterList {
        file_name: "ublock-unbreak.txt",
        url: "https://ublockorigin.github.io/uAssets/filters/unbreak.min.txt",
        trusted: true,
    },
    FilterList {
        file_name: "peter-lowe.txt",
        url: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext",
        trusted: false,
    },
];

pub const RESOURCES_FILE_NAME: &str = "resources.json";
pub const RESOURCES_URL: &str = "https://raw.githubusercontent.com/ghostery/adblocker/master/packages/adblocker/assets/ublock-origin/resources.json";
pub const ENGINE_FILE_NAME: &str = "engine.dat";
const MAXIMUM_AGE: Duration = Duration::from_secs(7 * 24 * 60 * 60);
const MAXIMUM_DOWNLOAD_BYTES: u64 = 64 * 1024 * 1024;

fn downloaded_files() -> impl Iterator<Item = &'static str> {
    FILTER_LISTS
        .iter()
        .map(|list| list.file_name)
        .chain(std::iter::once(RESOURCES_FILE_NAME))
}

pub fn needs_refresh(directory: &Path) -> bool {
    downloaded_files().any(|file_name| {
        let modified =
            fs::metadata(directory.join(file_name)).and_then(|metadata| metadata.modified());
        match modified {
            Ok(modified) => SystemTime::now()
                .duration_since(modified)
                .is_ok_and(|age| age > MAXIMUM_AGE),
            Err(_) => true,
        }
    })
}

fn write_atomically(path: &Path, contents: &[u8]) -> std::io::Result<()> {
    let temporary = path.with_extension("partial");
    fs::write(&temporary, contents)?;
    fs::rename(&temporary, path)
}

fn download(url: &str) -> Result<String, ureq::Error> {
    ureq::get(url)
        .call()?
        .body_mut()
        .with_config()
        .limit(MAXIMUM_DOWNLOAD_BYTES)
        .read_to_string()
}

pub fn download_all(directory: &Path) -> Result<(), String> {
    fs::create_dir_all(directory)
        .map_err(|error| format!("cannot create {}: {error}", directory.display()))?;
    let sources = FILTER_LISTS
        .iter()
        .map(|list| (list.file_name, list.url))
        .chain(std::iter::once((RESOURCES_FILE_NAME, RESOURCES_URL)));
    for (file_name, url) in sources {
        let body = download(url).map_err(|error| format!("download of {url} failed: {error}"))?;
        write_atomically(&directory.join(file_name), body.as_bytes())
            .map_err(|error| format!("cannot write {file_name}: {error}"))?;
    }
    Ok(())
}

pub fn lists_present(directory: &Path) -> bool {
    downloaded_files().all(|file_name| directory.join(file_name).is_file())
}

pub fn build_engine(directory: &Path) -> Result<Engine, String> {
    let mut filter_set = FilterSet::new(false);
    for list in &FILTER_LISTS {
        let path = directory.join(list.file_name);
        let text = fs::read_to_string(&path)
            .map_err(|error| format!("cannot read {}: {error}", path.display()))?;
        let permissions = if list.trusted {
            TRUSTED_PERMISSION
        } else {
            PermissionMask::default()
        };
        filter_set.add_filter_list(
            text,
            ParseOptions {
                permissions,
                ..ParseOptions::default()
            },
        );
    }
    let mut engine = Engine::new_with_filter_set(filter_set);
    attach_resources(&mut engine, directory)?;
    Ok(engine)
}

pub fn attach_resources(engine: &mut Engine, directory: &Path) -> Result<(), String> {
    let path = directory.join(RESOURCES_FILE_NAME);
    let json = fs::read_to_string(&path)
        .map_err(|error| format!("cannot read {}: {error}", path.display()))?;
    let resources = parse_resource_bundle(&json)
        .map_err(|error| format!("cannot parse {}: {error}", path.display()))?;
    engine.use_resources(resources);
    Ok(())
}

pub fn engine_path(directory: &Path) -> PathBuf {
    directory.join(ENGINE_FILE_NAME)
}

pub fn load_serialized_engine(directory: &Path) -> Result<Engine, String> {
    let path = engine_path(directory);
    let bytes =
        fs::read(&path).map_err(|error| format!("cannot read {}: {error}", path.display()))?;
    let mut engine = Engine::default();
    engine
        .deserialize(&bytes)
        .map_err(|error| format!("cannot deserialize {}: {error:?}", path.display()))?;
    attach_resources(&mut engine, directory)?;
    Ok(engine)
}

pub fn save_serialized_engine(engine: &Engine, directory: &Path) -> Result<(), String> {
    let path = engine_path(directory);
    write_atomically(&path, &engine.serialize())
        .map_err(|error| format!("cannot write {}: {error}", path.display()))
}
