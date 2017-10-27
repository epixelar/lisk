BEGIN;

/* Migrate blocks table */
/* Rename all columns for new schema */
ALTER TABLE blocks
RENAME id TO "block_id";
ALTER TABLE blocks
RENAME "rowId" TO "row_id";
ALTER TABLE blocks
RENAME "previousBlock" TO "previous_block_id";
ALTER TABLE blocks
RENAME "numberOfTransactions" TO "total_transactions";
ALTER TABLE blocks
RENAME "totalAmount" TO "total_amount";
ALTER TABLE blocks
RENAME "totalFee" TO "total_fee";
ALTER TABLE blocks
RENAME "payloadLength" TO "payload_length";
ALTER TABLE blocks
RENAME "payloadHash" TO "payload_hash";
ALTER TABLE blocks
RENAME "generatorPublicKey" TO "generator_public_key";
ALTER TABLE blocks
RENAME "blockSignature" TO "signature";

DROP TABLE IF EXISTS accounts;

CREATE TABLE "public".accounts (
	address              varchar(22)  NOT NULL,
	transaction_id       varchar(20)  ,
	public_key           bytea  ,
	public_key_transaction_id varchar(20)  ,
	balance              bigint DEFAULT 0 NOT NULL,
	CONSTRAINT pk_accounts PRIMARY KEY ( address ),
	CONSTRAINT idx_accounts UNIQUE ( public_key ) ,
	CONSTRAINT idx_accounts_0 UNIQUE ( transaction_id )
 );

 CREATE TABLE "public".transactions (
 	transaction_id       varchar(20)  NOT NULL,
 	row_id               serial  NOT NULL,
 	block_id             varchar(20)  NOT NULL,
 	"type"               smallint  NOT NULL,
 	"timestamp"          integer  NOT NULL,
 	sender_public_key    bytea  NOT NULL,
 	sender_address       varchar(22)  NOT NULL,
 	recipient_address    varchar(22)  ,
 	amount               bigint  NOT NULL,
 	fee                  bigint  NOT NULL,
 	signature            bytea  NOT NULL,
 	second_signature     bytea  ,
 	signatures           text  ,
 	CONSTRAINT pk_transactions PRIMARY KEY ( transaction_id ),
 	CONSTRAINT pk_transactions_4 UNIQUE ( transaction_id, sender_address, sender_public_key, recipient_address )
  );

	/* Rename transfers shit */
			ALTER TABLE transfer
			RENAME "transactionId" TO "transaction_id";

  -- Create new data type which will store block rewards info
--  CREATE OR REPLACE TYPE blockRewards AS (supply bigint, start int, distance bigint, milestones bigint[][]);

 -- Begin functions:
 CREATE OR REPLACE FUNCTION public.calcblockreward(block_height integer)
  RETURNS bigint
  LANGUAGE plpgsql
  IMMUTABLE
 AS $function$ DECLARE r blockRewards; mile int; BEGIN IF block_height IS NULL OR block_height <= 0 THEN RETURN NULL; END IF; SELECT * FROM getBlockRewards() INTO r; IF block_height < r.start THEN RETURN 0; END IF; mile := FLOOR((block_height-r.start)/r.distance)+1; IF mile > array_length(r.milestones, 1) THEN mile := array_length(r.milestones, 1); END IF; RETURN r.milestones[mile]; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.calcsupply(block_height integer)
  RETURNS bigint
  LANGUAGE plpgsql
  IMMUTABLE
 AS $function$ DECLARE r blockRewards; mile int; BEGIN IF block_height IS NULL OR block_height <= 0 THEN RETURN NULL; END IF; SELECT * FROM getBlockRewards() INTO r; IF block_height < r.start THEN RETURN r.supply; END IF; mile := FLOOR((block_height-r.start)/r.distance)+1; IF mile > array_length(r.milestones, 1) THEN mile := array_length(r.milestones, 1); END IF; FOR m IN 1..mile LOOP IF m = mile THEN r.supply := r.supply + (block_height-r.start+1-r.distance*(m-1))*r.milestones[m]; ELSE r.supply := r.supply + r.distance*r.milestones[m]; END IF; END LOOP; RETURN r.supply; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.calcsupply_test(height_start integer, height_end integer, expected_reward bigint)
  RETURNS boolean
  LANGUAGE plpgsql
  IMMUTABLE
 AS $function$ DECLARE supply bigint; prev_supply bigint; BEGIN SELECT calcSupply(height_start-1) INTO prev_supply; FOR height IN height_start..height_end LOOP SELECT calcSupply(height) INTO supply; IF (prev_supply+expected_reward) <> supply THEN RETURN false; END IF; prev_supply := supply; END LOOP; RETURN true; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.delegate_change_ranks_update()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ BEGIN PERFORM delegates_rank_update(); RETURN NULL; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.delegates_forged_blocks_cnt_update()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ BEGIN IF (TG_OP = 'INSERT') THEN UPDATE delegates SET blocks_forged_cnt = blocks_forged_cnt+1 WHERE public_key = NEW."generator_public_key"; ELSIF (TG_OP = 'DELETE') THEN UPDATE delegates SET blocks_forged_cnt = blocks_forged_cnt-1 WHERE public_key = OLD."generator_public_key"; END IF; RETURN NULL; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.delegates_rank_update()
  RETURNS TABLE(updated integer)
  LANGUAGE plpgsql
 AS $function$ BEGIN RETURN QUERY WITH new AS (SELECT row_number() OVER (ORDER BY voters_balance DESC, public_key ASC) AS rank, transaction_id FROM delegates), updated AS (UPDATE delegates SET rank = new.rank FROM new WHERE delegates.transaction_id = new.transaction_id RETURNING 1) SELECT COUNT(1)::INT FROM updated; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.delegates_update_on_block()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ BEGIN IF (TG_OP = 'INSERT') AND (NEW.height != 1) THEN PERFORM outsiders_update(); END IF; PERFORM delegates_voters_cnt_update(); PERFORM delegates_voters_balance_update(); PERFORM delegates_rank_update(); IF (TG_OP = 'DELETE') THEN PERFORM outsiders_rollback(ENCODE(OLD."generator_public_key", 'hex')); END IF; IF (TG_OP = 'INSERT') THEN PERFORM pg_notify('round-closed', json_build_object('round', CEIL((NEW.height+1) / 101::float)::int, 'list', generateDelegatesList(CEIL((NEW.height+1) / 101::float)::int, ARRAY(SELECT ENCODE(public_key, 'hex') AS public_key FROM delegates ORDER BY rank ASC LIMIT 101)))::text); ELSIF (TG_OP = 'DELETE') THEN PERFORM pg_notify('round-reopened', json_build_object('round', CEIL((OLD.height) / 101::float)::int, 'list', generateDelegatesList(CEIL((OLD.height) / 101::float)::int, ARRAY(SELECT ENCODE(public_key, 'hex') AS public_key FROM delegates ORDER BY rank ASC LIMIT 101)))::text); END IF; RETURN NULL; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.delegates_voters_balance_update()
  RETURNS TABLE(updated integer)
  LANGUAGE plpgsql
 AS $function$ BEGIN RETURN QUERY WITH last_round AS (SELECT (CASE WHEN height < 101 THEN 1 ELSE height END) AS height FROM blocks WHERE height % 101 = 0 OR height = 1 ORDER BY height DESC LIMIT 1), current_round_txs AS (SELECT t.id FROM transactions t LEFT JOIN blocks b ON b.id = t.block_id WHERE b.height > (SELECT height FROM last_round)), voters AS (SELECT DISTINCT ON (voter_address) voter_address FROM votes_details), balances AS ( (SELECT UPPER("sender_address") AS address, -SUM(amount+fee) AS amount FROM transactions GROUP BY UPPER("sender_address")) UNION ALL (SELECT UPPER("sender_address") AS address, SUM(amount+fee) AS amount FROM transactions WHERE id IN (SELECT * FROM current_round_txs) GROUP BY UPPER("sender_address")) UNION ALL (SELECT UPPER("recipient_address") AS address, SUM(amount) AS amount FROM transactions WHERE "recipient_address" IS NOT NULL GROUP BY UPPER("recipient_address")) UNION ALL (SELECT UPPER("recipient_address") AS address, -SUM(amount) AS amount FROM transactions WHERE id IN (SELECT * FROM current_round_txs) AND "recipient_address" IS NOT NULL GROUP BY UPPER("recipient_address")) UNION ALL (SELECT d.address, d.fees+d.rewards AS amount FROM delegates d) ), filtered AS (SELECT * FROM balances WHERE address IN (SELECT * FROM voters)), accounts AS (SELECT b.address, SUM(b.amount) AS balance FROM filtered b GROUP BY b.address), updated AS (UPDATE delegates SET voters_balance = balance FROM (SELECT d.public_key, ( (SELECT COALESCE(SUM(balance), 0) AS balance FROM accounts WHERE address IN (SELECT v.voter_address FROM (SELECT DISTINCT ON (voter_address) voter_address, type FROM votes_details WHERE delegate_public_key = d.public_key AND height <= (SELECT height FROM last_round) ORDER BY voter_address, timestamp DESC ) v WHERE v.type = 'add' ) ) ) FROM delegates d) dd WHERE delegates.public_key = dd.public_key RETURNING 1) SELECT COUNT(1)::INT FROM updated; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.delegates_voters_cnt_update()
  RETURNS TABLE(updated integer)
  LANGUAGE plpgsql
 AS $function$ BEGIN RETURN QUERY WITH last_round AS (SELECT (CASE WHEN height < 101 THEN 1 ELSE height END) AS height FROM blocks WHERE height % 101 = 0 OR height = 1 ORDER BY height DESC LIMIT 1), updated AS (UPDATE delegates SET voters_cnt = cnt FROM (SELECT d.public_key, (SELECT COUNT(1) AS cnt FROM (SELECT DISTINCT ON (voter_address) voter_address, delegate_public_key, type FROM votes_details WHERE delegate_public_key = d.public_key AND height <= (SELECT height FROM last_round) ORDER BY voter_address, timestamp DESC ) v WHERE type = 'add' ) FROM delegates d ) dd WHERE delegates.public_key = dd.public_key RETURNING 1) SELECT COUNT(1)::INT FROM updated; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.generatedelegateslist(round integer, delegates text[])
  RETURNS text[]
  LANGUAGE plpgsql
  IMMUTABLE
 AS $function$ DECLARE i int; x int; n int; old text; hash bytea; len int; BEGIN IF round IS NULL OR round < 1 OR delegates IS NULL OR array_length(delegates, 1) IS NULL OR array_length(delegates, 1) < 1 THEN RAISE invalid_parameter_value USING MESSAGE = 'Invalid parameters supplied'; END IF; hash := digest(round::text, 'sha256'); len := array_length(delegates, 1); i := 0; LOOP EXIT WHEN i >= 101; x := 0; LOOP EXIT WHEN x >= 4 OR i >= len; n := get_byte(hash, x) % len; old := delegates[n+1]; delegates[n+1] = delegates[i+1]; delegates[i+1] = old; i := i + 1; x := x + 1; END LOOP; hash := digest(hash, 'sha256'); i := i + 1; END LOOP; RETURN delegates; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.getblockrewards()
  RETURNS blockrewards
  LANGUAGE plpgsql
  IMMUTABLE
 AS $function$ DECLARE res blockRewards; supply bigint = 10000000000000000; start int = 1451520; distance bigint = 3000000; milestones bigint[] = ARRAY[ 500000000, 400000000, 300000000, 200000000, 100000000 ]; BEGIN res.supply = supply; res.start = start; res.distance = distance; res.milestones = milestones; RETURN res; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.getdelegateslist()
  RETURNS text[]
  LANGUAGE plpgsql
 AS $function$ DECLARE list text[]; BEGIN SELECT generateDelegatesList( (SELECT CEIL((height+1) / 101::float)::int AS round FROM blocks ORDER BY height DESC LIMIT 1), ARRAY(SELECT ENCODE(public_key, 'hex') AS public_key FROM delegates ORDER BY rank ASC LIMIT 101) ) INTO list; RETURN list; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.on_transaction_delete()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ DECLARE sender_address VARCHAR(22); recipient_address VARCHAR(22); BEGIN IF OLD."sender_address" IS NOT NULL THEN UPDATE accounts SET balance = accounts.balance+(OLD.amount+OLD.fee) WHERE accounts.address = OLD."sender_address"; END IF; IF OLD."recipient_address" IS NOT NULL THEN UPDATE accounts SET balance = accounts.balance-OLD.amount WHERE accounts.address = OLD."recipient_address"; END IF; RETURN NULL; END $function$
 ;

 -- Create trigger that will execute 'on_transaction_delete' function before deletion of transaction
 CREATE CONSTRAINT TRIGGER on_transaction_delete
 	AFTER DELETE ON transactions
 	DEFERRABLE INITIALLY DEFERRED
 	FOR EACH ROW
 	EXECUTE PROCEDURE on_transaction_delete();


 CREATE OR REPLACE FUNCTION public.on_transaction_insert()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ DECLARE sender_address VARCHAR(22); sender_public_key BYTEA; recipient_address VARCHAR(22); BEGIN SELECT address, public_key INTO sender_address, sender_public_key FROM accounts WHERE address = NEW."sender_address"; SELECT address INTO recipient_address FROM accounts WHERE address = NEW."recipient_address"; IF sender_address IS NULL THEN INSERT INTO accounts (transaction_id, public_key, public_key_transaction_id, address) VALUES (NEW.id, NEW."sender_public_key", NEW.id, NEW."sender_address"); ELSIF sender_public_key IS NULL THEN UPDATE accounts SET public_key = NEW."sender_public_key", public_key_transaction_id = NEW.id WHERE accounts.address = NEW."sender_address"; ELSIF sender_public_key != NEW."sender_public_key" THEN RAISE check_violation USING MESSAGE = 'Transaction invalid - cannot change account public key'; END IF; IF recipient_address IS NULL AND NEW."recipient_address" IS NOT NULL THEN INSERT INTO accounts (transaction_id, address) VALUES (NEW.id, NEW."recipient_address"); END IF; IF NEW."sender_address" IS NOT NULL THEN UPDATE accounts SET balance = accounts.balance-(NEW.amount+NEW.fee) WHERE accounts.address = NEW."sender_address"; END IF; IF NEW."recipient_address" IS NOT NULL THEN UPDATE accounts SET balance = accounts.balance+NEW.amount WHERE accounts.address = NEW."recipient_address"; END IF; RETURN NULL; END $function$
 ;

 -- Create trigger that will execute 'on_transaction_insert' function after insertion of transaction
 CREATE TRIGGER on_transaction_insert
 	AFTER INSERT ON transactions
 	FOR EACH ROW
 	EXECUTE PROCEDURE on_transaction_insert();


 CREATE OR REPLACE FUNCTION public.outsiders_rollback(last_block_forger text)
  RETURNS TABLE(updated integer)
  LANGUAGE plpgsql
 AS $function$ BEGIN RETURN QUERY WITH last_round AS (SELECT CEIL(height / 101::float)::int AS round FROM blocks ORDER BY height DESC LIMIT 1), updated AS (UPDATE delegates d SET blocks_missed_cnt = blocks_missed_cnt-1 WHERE ENCODE(d.public_key, 'hex') IN ( SELECT outsider FROM UNNEST(getDelegatesList()) outsider WHERE outsider NOT IN ( SELECT ENCODE(b."generator_public_key", 'hex') FROM blocks b WHERE CEIL(b.height / 101::float)::int = (SELECT round FROM last_round) ) AND outsider <> last_block_forger ) RETURNING 1 ) SELECT COUNT(1)::INT FROM updated; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.outsiders_update()
  RETURNS TABLE(updated integer)
  LANGUAGE plpgsql
 AS $function$ BEGIN RETURN QUERY WITH last_round AS (SELECT CEIL(height / 101::float)::int AS round FROM blocks ORDER BY height DESC LIMIT 1), updated AS (UPDATE delegates d SET blocks_missed_cnt = blocks_missed_cnt+1 WHERE ENCODE(d.public_key, 'hex') IN ( SELECT outsider FROM UNNEST(getDelegatesList()) outsider WHERE outsider NOT IN ( SELECT ENCODE(b."generator_public_key", 'hex') FROM blocks b WHERE CEIL(b.height / 101::float)::int = (SELECT round FROM last_round) ) ) RETURNING 1 ) SELECT COUNT(1)::INT FROM updated; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.public_key_rollback()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ BEGIN NEW.public_key = NULL; RETURN NEW; END $function$
;

 -- Create trigger that will execute 'pk_rollback' when 'pk_tx_id' is set to NULL
 CREATE TRIGGER public_key_rollback
 	BEFORE UPDATE ON accounts
 	FOR EACH ROW
 	WHEN (OLD.public_key_transaction_id IS NOT NULL AND NEW.public_key_transaction_id IS NULL)
 	EXECUTE PROCEDURE pk_rollback();

 CREATE OR REPLACE FUNCTION public.revert_mem_account()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ BEGIN IF NEW."address" <> OLD."address" THEN RAISE WARNING 'Reverting change of address from % to %', OLD."address", NEW."address"; NEW."address" = OLD."address"; END IF; IF NEW."u_username" <> OLD."u_username" AND OLD."u_username" IS NOT NULL THEN RAISE WARNING 'Reverting change of u_username from % to %', OLD."u_username", NEW."u_username"; NEW."u_username" = OLD."u_username"; END IF; IF NEW."username" <> OLD."username" AND OLD."username" IS NOT NULL THEN RAISE WARNING 'Reverting change of username from % to %', OLD."username", NEW."username"; NEW."username" = OLD."username"; END IF; IF NEW."virgin" <> OLD."virgin" AND OLD."virgin" = 0 THEN RAISE WARNING 'Reverting change of virgin from % to %', OLD."virgin", NEW."virgin"; NEW."virgin" = OLD."virgin"; END IF; IF NEW."publicKey" <> OLD."publicKey" AND OLD."virgin" = 0 AND OLD."publicKey" IS NOT NULL THEN RAISE WARNING 'Reverting change of publicKey from % to %', ENCODE(OLD."publicKey", 'hex'), ENCODE(NEW."publicKey", 'hex'); NEW."publicKey" = OLD."publicKey"; END IF; IF NEW."secondPublicKey" <> OLD."secondPublicKey" AND OLD."secondPublicKey" IS NOT NULL THEN RAISE WARNING 'Reverting change of secondPublicKey from % to %', ENCODE(OLD."secondPublicKey", 'hex'), ENCODE(NEW."secondPublicKey", 'hex'); NEW."secondPublicKey" = OLD."secondPublicKey"; END IF; RETURN NEW; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.round_rewards_delete()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ BEGIN WITH r AS (SELECT public_key, SUM(fees) AS fees, SUM(reward) AS rewards FROM rounds_rewards WHERE round = (CEIL(OLD.height / 101::float)::int) GROUP BY public_key) UPDATE delegates SET rewards = delegates.rewards-r.rewards, fees = delegates.fees-r.fees FROM r WHERE delegates.public_key = r.public_key; WITH r AS (SELECT public_key, SUM(fees) AS fees, SUM(reward) AS rewards FROM rounds_rewards WHERE round = (CEIL(OLD.height / 101::float)::int) GROUP BY public_key) UPDATE mem_accounts SET balance = mem_accounts.balance-r.rewards-r.fees, u_balance = mem_accounts.u_balance-r.rewards-r.fees FROM r WHERE mem_accounts."publicKey" = r.public_key; DELETE FROM rounds_rewards WHERE round = (CEIL(OLD.height / 101::float)::int); RETURN NULL; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.round_rewards_insert()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ BEGIN WITH round AS ( SELECT b.timestamp, b.height, b."generator_public_key" AS public_key, b."totalFee" * COALESCE(e.fees_factor, 1) AS fees, b.reward * COALESCE(e.rewards_factor, 1) AS reward, COALESCE(e.fees_bonus, 0) AS fb FROM blocks b LEFT JOIN rounds_exceptions e ON CEIL(b.height / 101::float)::int = e.round WHERE CEIL(b.height / 101::float)::int = CEIL(NEW.height / 101::float)::int AND b.height > 1 ), fees AS (SELECT SUM(fees) + fb AS total, FLOOR((SUM(fees) + fb) / 101) AS single FROM round GROUP BY fb), last AS (SELECT public_key, timestamp FROM round ORDER BY height DESC LIMIT 1) INSERT INTO rounds_rewards SELECT round.height, last.timestamp, (fees.single + (CASE WHEN last.public_key = round.public_key AND last.timestamp = round.timestamp THEN (fees.total - fees.single * 101) ELSE 0 END)) AS fees, round.reward, CEIL(round.height / 101::float)::int, round.public_key FROM last, fees, round ORDER BY round.height ASC; WITH r AS (SELECT public_key, SUM(fees) AS fees, SUM(reward) AS rewards FROM rounds_rewards WHERE round = (CEIL(NEW.height / 101::float)::int) GROUP BY public_key) UPDATE delegates SET rewards = delegates.rewards+r.rewards, fees = delegates.fees+r.fees FROM r WHERE delegates.public_key = r.public_key; WITH r AS (SELECT public_key, SUM(fees) AS fees, SUM(reward) AS rewards FROM rounds_rewards WHERE round = (CEIL(NEW.height / 101::float)::int) GROUP BY public_key) UPDATE mem_accounts SET balance = mem_accounts.balance+r.rewards+r.fees, u_balance = mem_accounts.u_balance+r.rewards+r.fees FROM r WHERE mem_accounts."publicKey" = r.public_key; RETURN NULL; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.rounds_rewards_init()
  RETURNS void
  LANGUAGE plpgsql
 AS $function$ DECLARE row record; BEGIN RAISE NOTICE 'Calculating rewards for rounds, please wait...'; FOR row IN SELECT CEIL(height / 101::float)::int AS round FROM blocks WHERE height % 101 = 0 AND height NOT IN (SELECT height FROM rounds_rewards) GROUP BY CEIL(height / 101::float)::int ORDER BY CEIL(height / 101::float)::int ASC LOOP WITH round AS ( SELECT b.timestamp, b.height, b."generator_public_key" AS public_key, b."totalFee" * COALESCE(e.fees_factor, 1) AS fees, b.reward * COALESCE(e.rewards_factor, 1) AS reward, COALESCE(e.fees_bonus, 0) AS fb FROM blocks b LEFT JOIN rounds_exceptions e ON CEIL(b.height / 101::float)::int = e.round WHERE CEIL(b.height / 101::float)::int = row.round AND b.height > 1 ), fees AS (SELECT SUM(fees) + fb AS total, FLOOR((SUM(fees) + fb) / 101) AS single FROM round GROUP BY fb), last AS (SELECT public_key, timestamp FROM round ORDER BY height DESC LIMIT 1) INSERT INTO rounds_rewards SELECT round.height, last.timestamp, (fees.single + (CASE WHEN last.public_key = round.public_key AND last.timestamp = round.timestamp THEN (fees.total - fees.single * 101) ELSE 0 END)) AS fees, round.reward, CEIL(round.height / 101::float)::int, round.public_key FROM last, fees, round ORDER BY round.height ASC; END LOOP; RETURN; END $function$
 ;

DROP FUNCTION public.validatemembalances();

 CREATE OR REPLACE FUNCTION public.validatemembalances()
  RETURNS TABLE(address character varying, public_key text, username character varying, blockchain bigint, memory bigint, diff bigint)
  LANGUAGE plpgsql
 AS $function$ BEGIN RETURN QUERY WITH balances AS ( (SELECT UPPER("sender_address") AS address, -SUM(amount+fee) AS amount FROM transactions GROUP BY UPPER("sender_address")) UNION ALL (SELECT UPPER("recipient_address") AS address, SUM(amount) AS amount FROM transactions WHERE "recipient_address" IS NOT NULL GROUP BY UPPER("recipient_address")) UNION ALL (SELECT a.address, r.amount FROM (SELECT r.public_key, SUM(r.fees) + SUM(r.reward) AS amount FROM rounds_rewards r GROUP BY r.public_key) r LEFT JOIN mem_accounts a ON r.public_key = a."publicKey" ) ), accounts AS (SELECT b.address, SUM(b.amount) AS balance FROM balances b GROUP BY b.address) SELECT m.address, ENCODE(m."publicKey", 'hex') AS public_key, m.username, a.balance::BIGINT AS blockchain, m.balance::BIGINT AS memory, (m.balance-a.balance)::BIGINT AS diff FROM accounts a LEFT JOIN mem_accounts m ON a.address = m.address WHERE a.balance <> m.balance; END $function$
 ;

 CREATE OR REPLACE FUNCTION public.vote_insert()
  RETURNS trigger
  LANGUAGE plpgsql
 AS $function$ BEGIN INSERT INTO votes_details SELECT r.transaction_id, r.voter_address, (CASE WHEN substring(vote, 1, 1) = '+' THEN 'add' ELSE 'rem' END) AS type, r.timestamp, r.height, DECODE(substring(vote, 2), 'hex') AS delegate_public_key FROM ( SELECT v."transactionId" AS transaction_id, t."sender_address" AS voter_address, b.timestamp AS timestamp, b.height, regexp_split_to_table(v.votes, ',') AS vote FROM votes v, transactions t, blocks b WHERE v."transactionId" = NEW."transactionId" AND v."transactionId" = t.id AND b.id = t."blockId" ) AS r ORDER BY r.timestamp ASC; RETURN NULL; END $function$
 ;


 -- Apply transactions into new table, to populate new accounts table
  INSERT INTO "public".transactions ( transaction_id, row_id, block_id, type, timestamp, sender_public_key, sender_address, recipient_address, amount, fee, signature, second_signature, signatures)
  SELECT
  	t."id", t."rowId", t."blockId", t.type, t.timestamp, t."senderPublicKey", t."senderId", t."recipientId", t.amount, t.fee, t.signature, t."signSignature", t.signatures
  FROM
  	trs t;


/* Rename delegates shit */
		ALTER TABLE delegates
		RENAME tx_id TO "transaction_id";
		ALTER TABLE delegates
		RENAME pk TO "public_key";

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

/* Create new indexes */

-- accounts indexes
CREATE INDEX idx_accounts_1 ON "public".accounts ( public_key_transaction_id );
CREATE INDEX idx_accounts_address_upper ON "public".accounts ( upper((address)::text) );
CREATE INDEX idx_accounts_balance ON "public".accounts ( balance );

-- Blocks indexes/constraints
ALTER SEQUENCE "public"."blocks_rowId_seq" RENAME TO "seq_blocks_row_id";
ALTER INDEX "blocks_pkey" RENAME TO "idx_blocks_pkey";
ALTER INDEX "blocks_height"  RENAME TO "idx_blocks_height";
ALTER INDEX "blocks_previousBlock"  RENAME TO "idx_blocks_previous_block_id";
ALTER INDEX "blocks_generator_public_key"  RENAME TO "idx_blocks_generator_public_key";
ALTER INDEX "blocks_reward" RENAME TO "idx_blocks_reward";
ALTER INDEX "blocks_rounds"  RENAME TO "idx_blocks_rounds";
ALTER INDEX "blocks_timestamp"  RENAME TO "idx_blocks_timestamp";
ALTER INDEX "blocks_numberOfTransactions" RENAME TO "idx_blocks_total_transactions";
ALTER INDEX "blocks_rowId" RENAME TO "idx_blocks_row_id";
ALTER INDEX "blocks_totalAmount" RENAME TO "idx_blocks_total_amount";
ALTER INDEX "blocks_totalFee" RENAME TO "idx_blocks_total_fee";
ALTER TABLE "public".blocks DROP CONSTRAINT "blocks_previousBlock_fkey";
ALTER TABLE "public".blocks ADD CONSTRAINT "fkey_blocks_previous_block_id_fkey" FOREIGN KEY ( "previous_block_id" ) REFERENCES "public".blocks( block_id ) ON DELETE SET NULL;

-- Transactions indexes
CREATE INDEX idx_transactions_transaction_id ON "public".transactions ( transaction_id  );
CREATE INDEX idx_transactions_sender_address ON "public".transactions ( sender_address );
CREATE INDEX idx_transactions_recipient_address ON "public".transactions ( recipient_address );
CREATE INDEX idx_transactions_block_id ON "public".transactions ( block_id );

-- votes indexes
CREATE INDEX idx_votes_public_key ON "public".votes ( public_key );
CREATE INDEX idx_votes_transaction_id ON "public".votes ( transaction_id );
CREATE INDEX idx_votes_transactions_id ON "public".votes ( "transaction_id" );

-- Second signature indexes
CREATE INDEX idx_second_signature_transaction_id ON "public".second_signature ( "transaction_id" );
CREATE INDEX idx_public_key ON "public".second_signature ( "public_key" );
CREATE INDEX idx_second_public_key ON "public".second_signature ( "second_public_key" );

-- Multisignatures indexes
CREATE INDEX idx_multisignatures_master_transaction_id ON "public".multisignatures_master ( "transaction_id" );
CREATE INDEX idx_multisignatures_master_public_key ON "public".multisignatures_master ( public_key );
CREATE INDEX idx_multisignatures_member_transaction_id ON "public".multisignatures_member ( "transaction_id" );
CREATE INDEX idx_multisignatures_member_public_key ON "public".multisignatures_member ( public_key );

-- Dapps indexes
CREATE INDEX idx_dapps_name ON "public".dapps ( name );
CREATE INDEX idx_dapps_transactions_id ON "public".dapps ( "transaction_id" );

/* Begin cleanup of old tables */
	DROP VIEW blocks_list;
	DROP VIEW trs_list;
	DROP VIEW full_blocks_list;
	DROP TABLE dapps_old CASCADE;
	DROP TABLE votes_old CASCADE;
	DROP TABLE signatures CASCADE;
	DROP TABLE multisignatures CASCADE;
	DROP TABLE trs CASCADE;
	DROP TABLE mem_accounts2delegates CASCADE;
	DROP TABLE mem_accounts2u_delegates CASCADE;
	DROP TABLE mem_accounts2multisignatures CASCADE;
	DROP TABLE mem_accounts2u_multisignatures CASCADE;
	DROP TABLE mem_accounts CASCADE; -- bye bye mother fucker

-- Create new Foreign Key relations
ALTER TABLE "public".votes ADD CONSTRAINT "fkey_votes_transaction_id" FOREIGN KEY ( "transaction_id" ) REFERENCES "public".transactions( "transaction_id" ) ON DELETE CASCADE;
ALTER TABLE "public".intransfer ADD CONSTRAINT "fkey_intransfer_transaction_id" FOREIGN KEY ( "transaction_id" ) REFERENCES "public".transactions( "transaction_id" ) ON DELETE CASCADE;
ALTER TABLE "public".outtransfer ADD CONSTRAINT "fkey_outtransfer_transaction_id" FOREIGN KEY ( "transaction_id" ) REFERENCES "public".transactions( "transaction_id" ) ON DELETE CASCADE;
ALTER TABLE "public".multisignatures_master ADD CONSTRAINT "fkey_multisignatures_master_transaction_id" FOREIGN KEY ( "transaction_id" ) REFERENCES "public".transactions( "transaction_id" ) ON DELETE CASCADE;
ALTER TABLE "public".multisignatures_member ADD CONSTRAINT "fkey_multisignatures_member_transaction_id" FOREIGN KEY ( "transaction_id" ) REFERENCES "public".transactions( "transaction_id" ) ON DELETE CASCADE;
ALTER TABLE "public".second_signature ADD CONSTRAINT "fkey_second_signature_transaction_id" FOREIGN KEY ( "transaction_id" ) REFERENCES "public".transactions( "transaction_id" ) ON DELETE CASCADE;
ALTER TABLE "public".delegates ADD CONSTRAINT "fkey_delegates_transaction_id" FOREIGN KEY ( "transaction_id" ) REFERENCES "public".transactions( "transaction_id" ) ON DELETE CASCADE;



-- Recreate views

CREATE VIEW "public".accounts_list AS  SELECT a.address,
    a.public_key AS "publicKey",
    ss.second_public_key AS "secondPublicKey",
    d.name AS username,
    d.rank,
    d.fees,
    d.rewards,
    d.voters_balance AS votes,
    d.voters_cnt AS voters,
    d.blocks_forged_cnt AS "producedBlocks",
    d.blocks_missed_cnt AS "missedBlocks",
    mma.lifetime,
    mma.minimum AS min
   FROM accounts a,
    second_signature ss,
    delegates d,
    multisignatures_master mma,
    multisignatures_member mme;;

CREATE VIEW "public".blocks_list AS  SELECT b.block_id AS b_id,
    b.version AS b_version,
    b."timestamp" AS b_timestamp,
    b.height AS b_height,
    b."previous_block_id" AS "b_previousBlock",
    b."total_transactions" AS "b_numberOfTransactions",
    b."total_amount" AS "b_totalAmount",
    b."total_fee" AS "b_totalFee",
    b.reward AS b_reward,
    b."payload_length" AS "b_payloadLength",
    encode(b."payload_hash", 'hex'::text) AS "b_payloadHash",
    encode(b."generator_public_key", 'hex'::text) AS "b_generatorPublicKey",
    encode(b."signature", 'hex'::text) AS "b_blockSignature",
    (( SELECT (max(blocks.height) + 1)
           FROM blocks) - b.height) AS b_confirmations
   FROM blocks b;;

CREATE VIEW "public".transactions_list AS SELECT t.transaction_id AS t_id,
     b.height AS b_height,
     t.block_id AS "t_blockId",
     t.type AS t_type,
     t."timestamp" AS t_timestamp,
     t.sender_public_key AS "t_senderPublicKey",
     a.public_key AS "a_recipientPublicKey",
     upper((t.sender_address)::text) AS "t_senderId",
     upper((t.recipient_address)::text) AS "t_recipientId",
     t.amount AS t_amount,
     t.fee AS t_fee,
     encode(t.signature, 'hex'::text) AS t_signature,
     encode(t.second_signature, 'hex'::text) AS "t_signSignature",
     (( SELECT (blocks.height + 1)
                    FROM blocks
                 ORDER BY blocks.height DESC
                LIMIT 1) - b.height) AS confirmations
    FROM ((transactions t
        LEFT JOIN blocks b ON (((t.block_id)::text = (b.block_id)::text)))
        LEFT JOIN accounts a ON (((t.recipient_address)::text = (a.address)::text)));;

CREATE VIEW "public".full_blocks_list AS SELECT b.block_id AS b_id,
			     b.version AS b_version,
			     b."timestamp" AS b_timestamp,
			     b.height AS b_height,
			     b."previous_block_id" AS "b_previousBlock",
			     b."total_transactions" AS "b_numberOfTransactions",
			     b."total_amount" AS "b_totalAmount",
			     b."total_fee" AS "b_totalFee",
			     b.reward AS b_reward,
			     b."payload_length" AS "b_payloadLength",
			     encode(b."payload_hash", 'hex'::text) AS "b_payloadHash",
			     encode(b."generator_public_key", 'hex'::text) AS "b_generatorPublicKey",
			     encode(b."signature", 'hex'::text) AS "b_blockSignature",
			     t.transaction_id AS t_id,
			     t."row_id" AS "t_rowId",
			     t.type AS t_type,
			     t."timestamp" AS t_timestamp,
			     encode(t."sender_public_key", 'hex'::text) AS "t_senderPublicKey",
			     t."sender_address" AS "t_senderId",
			     t."recipient_address" AS "t_recipientId",
			     t.amount AS t_amount,
			     t.fee AS t_fee,
			     encode(t.signature, 'hex'::text) AS t_signature,
			     encode(t."second_signature", 'hex'::text) AS "t_signSignature",
			     encode(s."public_key", 'hex'::text) AS "s_publicKey",
			     d.name AS d_username,
			     v.votes AS v_votes,
			     m.minimum AS m_min,
			     m.lifetime AS m_lifetime,
			     --m.keysgroup AS m_keysgroup, Need to implement this shit with a select
			     dapp.name AS dapp_name,
			     dapp.description AS dapp_description,
			     dapp.tags AS dapp_tags,
			     dapp.type AS dapp_type,
			     dapp.link AS dapp_link,
			     dapp.category AS dapp_category,
			     dapp.icon AS dapp_icon,
			     it."dapp_id" AS "in_dappId",
			     ot."dapp_id" AS "ot_dappId",
			     ot."out_transaction_id" AS "ot_outTransactionId",
			     --encode(t."requester_public_key", 'hex'::text) AS "t_requesterPublicKey", What do we do with shit? Was uninmplemented and not in new schema
			     convert_from(tf.data, 'utf8'::name) AS tf_data,
			     t.signatures AS t_signatures
			    FROM (((((((((blocks b
			      LEFT JOIN transactions t ON (((t."block_id")::text = (b.block_id)::text)))
			      LEFT JOIN delegates d ON (((d.transaction_id)::text = (t.transaction_id)::text)))
			      LEFT JOIN votes v ON (((v."transaction_id")::text = (t.transaction_id)::text)))
			      LEFT JOIN second_signature s ON (((s."transaction_id")::text = (t.transaction_id)::text)))
			      LEFT JOIN multisignatures_master m ON (((m."transaction_id")::text = (t.transaction_id)::text)))
			      LEFT JOIN dapps dapp ON (((dapp."transaction_id")::text = (t.transaction_id)::text)))
			      LEFT JOIN intransfer it ON (((it."transaction_id")::text = (t.transaction_id)::text)))
			      LEFT JOIN outtransfer ot ON (((ot."transaction_id")::text = (t.transaction_id)::text)))
			      LEFT JOIN transfer tf ON (((tf."transaction_id")::text = (t.transaction_id)::text)));

COMMIT;

END;
