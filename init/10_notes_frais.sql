DROP TABLE IF EXISTS notes_frais CASCADE;

CREATE TABLE notes_frais (
    id SERIAL PRIMARY KEY,
    numero_note VARCHAR(50) NOT NULL,
    ligne_index INT NOT NULL,              -- index de ligne à l’intérieur de la note (1..N)
    ligne_uid TEXT,                        -- identifiant libre (non clé)
    nom VARCHAR(255) NOT NULL,
    date_depense DATE NOT NULL,
    nature VARCHAR(255),
    lieu VARCHAR(255),
    montant NUMERIC(10,2) NOT NULL,
    note_hash TEXT NOT NULL,               -- même valeur pour toutes les lignes d’une même note
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),

    -- Empêche les doublons de lignes dans une même note
    CONSTRAINT notes_frais_unique_note_ligne UNIQUE (note_hash, ligne_index)
);

-- Index utiles pour les recherches
CREATE INDEX idx_notes_frais_note_hash   ON notes_frais(note_hash);
CREATE INDEX idx_notes_frais_numero_note ON notes_frais(numero_note);
CREATE INDEX idx_notes_frais_date        ON notes_frais(date_depense);

