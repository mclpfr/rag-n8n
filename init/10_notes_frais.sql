\connect notes_frais;

-- === Table: notes_frais ==================================================
CREATE TABLE IF NOT EXISTS public.notes_frais
(
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero_facture   VARCHAR(50)  NOT NULL,
    nom              VARCHAR(100) NOT NULL,
    date_depense    DATE         NOT NULL,
    nature           VARCHAR(50)  NOT NULL,
    montant          NUMERIC(10,2) NOT NULL,
    facture_hash     VARCHAR(64)   NOT NULL,           -- empreinte du document
    created_at       TIMESTAMP     NOT NULL DEFAULT now()
);

-- Contrainte pour éviter doublons de factures identiques
CREATE UNIQUE INDEX IF NOT EXISTS uq_notes_frais_doc_hash
  ON public.notes_frais(facture_hash);

-- Index utiles pour les recherches
CREATE INDEX IF NOT EXISTS idx_notes_frais_date_depense ON public.notes_frais(date_depense);
CREATE INDEX IF NOT EXISTS idx_notes_frais_nom          ON public.notes_frais(nom);
CREATE INDEX IF NOT EXISTS idx_notes_frais_nature       ON public.notes_frais(nature);

