-- v2 has its own database; user_version is independent of Drift's v1 schema.
CREATE TABLE documents (
    id TEXT NOT NULL PRIMARY KEY,
    title TEXT NOT NULL,
    authors TEXT NOT NULL,
    journal TEXT,
    year TEXT,
    doi TEXT,
    keywords TEXT NOT NULL,
    contentHash TEXT,
    addedAt INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_documents_contentHash ON documents(contentHash)
    WHERE contentHash IS NOT NULL;
CREATE INDEX idx_documents_doi ON documents(doi);
CREATE INDEX idx_documents_addedAt ON documents(addedAt);

CREATE TABLE highlights (
    id TEXT NOT NULL PRIMARY KEY,
    docId TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    note TEXT,
    color TEXT NOT NULL,
    groupId TEXT,
    anchor TEXT,
    createdAt INTEGER NOT NULL
);
CREATE INDEX idx_highlights_docId ON highlights(docId);

CREATE TABLE history (
    docId TEXT NOT NULL PRIMARY KEY REFERENCES documents(id) ON DELETE CASCADE,
    openedAt INTEGER NOT NULL,
    progress REAL NOT NULL DEFAULT 0,
    anchorBlock TEXT
);

CREATE TABLE favorites (
    id TEXT NOT NULL PRIMARY KEY,
    emoji TEXT NOT NULL,
    name TEXT NOT NULL,
    createdAt INTEGER NOT NULL
);
CREATE TABLE favorite_documents (
    favoriteId TEXT NOT NULL REFERENCES favorites(id) ON DELETE CASCADE,
    docId TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    PRIMARY KEY (favoriteId, docId)
);

CREATE TABLE zotero_items (
    zoteroKey TEXT NOT NULL PRIMARY KEY,
    docId TEXT REFERENCES documents(id) ON DELETE CASCADE,
    version INTEGER NOT NULL
);
CREATE INDEX idx_zotero_items_docId ON zotero_items(docId);
CREATE TABLE settings (
    settingKey TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE meta (
    metaKey TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
);

-- Standalone index: triggers keep metadata and index in the same transaction.
CREATE VIRTUAL TABLE documents_fts USING fts5(
    id UNINDEXED, title, authors, journal, keywords, tokenize = 'otter_jieba'
);
CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN
    INSERT INTO documents_fts(rowid, id, title, authors, journal, keywords)
        VALUES (new.rowid, new.id, new.title, new.authors, new.journal, new.keywords);
END;
CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN
    DELETE FROM documents_fts WHERE rowid = old.rowid;
END;
CREATE TRIGGER documents_au AFTER UPDATE ON documents BEGIN
    DELETE FROM documents_fts WHERE rowid = old.rowid;
    INSERT INTO documents_fts(rowid, id, title, authors, journal, keywords)
        VALUES (new.rowid, new.id, new.title, new.authors, new.journal, new.keywords);
END;
