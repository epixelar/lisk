BEGIN;


 -- Apply transactions into new table, to populate new accounts table
  INSERT INTO "public".transactions ( transaction_id, row_id, block_id, type, timestamp, sender_public_key, sender_address, recipient_address, amount, fee, signature, second_signature, signatures)
  SELECT
  	t."id", t."rowId", t."blockId", t.type, t.timestamp, t."senderPublicKey", t."senderId", t."recipientId", t.amount, t.fee, t.signature, t."signSignature", t.signatures
  FROM
  	trs t;


			/* Rename transfers shit */
					ALTER TABLE transfer
					RENAME "transactionId" TO "transaction_id";

/* Delegates shit */
		ALTER TABLE delegates
		RENAME tx_id TO "transaction_id";
		ALTER TABLE delegates
		RENAME pk TO "public_key";
		ALTER TABLE delegates
		RENAME blocks_missed_cnt TO "blocks_missed_count";
		ALTER TABLE delegates
		RENAME blocks_forged_cnt TO "blocks_forged_count";

	/* Votes */

	ALTER TABLE votes rename to votes_old;

	CREATE TABLE "public".votes (
		transaction_id       varchar(20)  NOT NULL,
		public_key           bytea  NOT NULL,
		votes                text  NOT NULL
	 );

-- Populate votes table based on old data
	INSERT INTO "public".votes (transaction_id, public_key, votes)
	SELECT
		t."transaction_id",
		t."sender_public_key",
		v.votes
	FROM
		votes_old v,
		transactions t
	WHERE
		t."transaction_id" = v."transactionId";

	CREATE OR REPLACE TRIGGER vote_insert
		AFTER INSERT ON votes
		FOR EACH ROW
		EXECUTE PROCEDURE vote_insert();

	CREATE OR REPLACE FUNCTION public.vote_insert()
		 RETURNS trigger
		 LANGUAGE plpgsql
		AS $function$ BEGIN INSERT INTO votes_details SELECT r.transaction_id, r.voter_address, (CASE WHEN substring(vote, 1, 1) = '+' THEN 'add' ELSE 'rem' END) AS type, r.timestamp, r.height, DECODE(substring(vote, 2), 'hex') AS delegate_public_key FROM ( SELECT v."transaction_id" AS transaction_id, t."sender_address" AS voter_address, b.timestamp AS timestamp, b.height, regexp_split_to_table(v.votes, ',') AS vote FROM votes v, transactions t, blocks b WHERE v."transaction_id" = NEW."transaction_id" AND v."transaction_id" = t.id AND b.id = t."blockId" ) AS r ORDER BY r.timestamp ASC; RETURN NULL; END $function$
		;

/* Begin second signature migration */
	CREATE TABLE "public".second_signature (
		transaction_id       varchar(20)  NOT NULL,
		public_key           bytea  NOT NULL,
		second_public_key    bytea  NOT NULL,
		CONSTRAINT pk_second_signature PRIMARY KEY ( public_key )
	 );

	 INSERT INTO second_signature (transaction_id, public_key, second_public_key)
	    SELECT t.transaction_id, t."sender_public_key", ma."secondPublicKey"
	 FROM
	     "public".transactions t, mem_accounts ma
	 where
	     ma."secondPublicKey" IS NOT NULL and t."sender_address" = ma."address" and t.type=1;


/* Begin multisignatures migration */

CREATE TABLE "public".multisignatures_master (
	transaction_id       varchar(20)  NOT NULL,
	public_key           bytea  NOT NULL,
	lifetime             smallint  NOT NULL,
	minimum              smallint  NOT NULL,
	CONSTRAINT pk_multisignatures_master PRIMARY KEY ( public_key )
 );

CREATE TABLE "public".multisignatures_member (
	transaction_id       varchar(20)  NOT NULL,
	public_key           text  NOT NULL, -- I need to be bytea
	master_public_key    bytea  NOT NULL,
	CONSTRAINT pk_multisignature_members UNIQUE ( master_public_key , public_key )
 );

/* Populates multisignatures master table from blockchain */
 INSERT INTO "public".multisignatures_master (transaction_id, public_key, minimum, lifetime )
 SELECT t."id", t."senderPublicKey", ma."multimin", ma."multilifetime" FROM  mem_accounts ma, trs t
  WHERE t."type" = 4 and t."senderPublicKey" = ma."publicKey";

/* Populates multisignatures member from blockchain */
INSERT INTO "public".multisignatures_member (transaction_id, public_key, master_public_key )
SELECT mma."transaction_id",
substring(regexp_split_to_table(ms.keysgroup, E',') from 2 for 64), -- I need to cast to hex
 mma.public_key FROM  multisignatures ms, multisignatures_master mma where mma."transaction_id" = ms."transactionId";



/* Begin outtransfer migration */
 ALTER TABLE outtransfer
 RENAME "transactionId" TO "transaction_id";
 ALTER TABLE outtransfer
 RENAME "dappId" TO "dapp_id";
 ALTER TABLE outtransfer
 RENAME "outTransactionId" TO "out_transaction_id";


 /* Begin intransfer migration */
 ALTER TABLE intransfer
 RENAME "dappId" TO "dapp_id";
 ALTER TABLE intransfer
 RENAME "transactionId" TO "transaction_id";

 /* Begin dapps migration */
	ALTER TABLE dapps RENAME TO dapps_old;

	CREATE TABLE "public".dapps (
 	transaction_id       varchar(20)  NOT NULL,
 	name                 varchar(32)  NOT NULL,
 	description          varchar(160)  ,
 	tags                 varchar(160)  ,
 	link                 text  ,
 	type                 integer  NOT NULL,
 	category             integer  NOT NULL,
 	icon                 text  ,
 	owner_public_key     bytea  NOT NULL,
 	CONSTRAINT pk_dapps_transaction_id PRIMARY KEY ( transaction_id )
  );

 /* Populate new dapps table */
 INSERT INTO "public".dapps ( transaction_id, name, description, tags, link, type, category, icon, owner_public_key)
 SELECT DISTINCT d."transactionId",
 	d.name,
 	d.description,
 	d.tags,
 	d.link,
 	d.type,
 	d.category,
 	d.icon,
 	t."sender_public_key"
 FROM
 	transactions t, dapps_old d
 WHERE
 	t.type = 5 and d."transactionId" = t."transaction_id";

COMMIT;
END;
