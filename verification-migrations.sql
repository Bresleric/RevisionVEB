-- RevisionVEB — verification des migrations
--
-- A coller dans Supabase -> SQL Editor du projet qhvtqapasxekkumuztak.
-- Ne modifie rien : ce script ne fait que lire.
--
-- Chaque ligne doit afficher OK. Toute ligne A FAIRE indique le fichier a
-- executer.

SELECT * FROM (

    SELECT 1 AS ordre,
           'Doublons de balance purges' AS controle,
           CASE WHEN (SELECT count(*) - count(DISTINCT (exercice_id, account_number))
                      FROM balance_accounts) = 0
                THEN 'OK'
                ELSE 'A FAIRE — ' || (SELECT count(*) - count(DISTINCT (exercice_id, account_number))
                                      FROM balance_accounts)::text || ' doublons'
           END AS etat,
           'migration-purge-doublons-balance.sql' AS fichier

    UNION ALL SELECT 2,
           'Index unique sur balance_accounts',
           CASE WHEN EXISTS (SELECT 1 FROM pg_indexes
                             WHERE indexname = 'balance_accounts_exercice_compte_key')
                THEN 'OK' ELSE 'A FAIRE' END,
           'migration-purge-doublons-balance.sql'

    UNION ALL SELECT 3,
           'Table cycle_pieces',
           CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables
                             WHERE table_schema = 'public' AND table_name = 'cycle_pieces')
                THEN 'OK' ELSE 'A FAIRE' END,
           'migration-cycle-pieces.sql'

    UNION ALL SELECT 4,
           'Policy RLS sur cycle_pieces',
           CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cycle_pieces')
                THEN 'OK' ELSE 'A FAIRE — table bloquee en lecture ET en ecriture' END,
           'migration-cycle-pieces.sql'

    UNION ALL SELECT 5,
           'Colonne points_en_suspens.account_number',
           CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                             WHERE table_name = 'points_en_suspens'
                               AND column_name = 'account_number')
                THEN 'OK' ELSE 'A FAIRE' END,
           'migration-points-compte.sql'

    UNION ALL SELECT 6,
           'Colonnes de ventilation sur recon_items',
           CASE WHEN (SELECT count(*) FROM information_schema.columns
                      WHERE table_name = 'recon_items'
                        AND column_name IN ('compte_charge', 'montant_ht',
                                            'taux_tva', 'montant_tva')) = 4
                THEN 'OK'
                ELSE 'A FAIRE — ' ||
                     (4 - (SELECT count(*) FROM information_schema.columns
                           WHERE table_name = 'recon_items'
                             AND column_name IN ('compte_charge', 'montant_ht',
                                                 'taux_tva', 'montant_tva')))::text
                     || ' colonne(s) manquante(s)'
           END,
           'migration-recon-ventilation.sql'

) AS controles
ORDER BY ordre;
