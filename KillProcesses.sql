USE mysql;

DROP PROCEDURE IF EXISTS KillProcesses;
DELIMITER //

CREATE PROCEDURE KillProcesses()
BEGIN 
    DECLARE ProcessCount INT;
	DECLARE ProcessID INT;
	DECLARE IsProcessRuning INT;
	DECLARE KillProcess INT; 

--	INSERT INTO db1.logtable (experiment_id, session_id, session_ordinal, insert_ordinal, hostname, target_IP)
--	VALUES ('---', '---', 0, 0, '---', 0,0,0,0);
	
	SELECT COUNT(id) INTO ProcessCount FROM INFORMATION_SCHEMA.PROCESSLIST WHERE db = 'db1';   
	SELECT id,user,host,db,command,state,info FROM INFORMATION_SCHEMA.PROCESSLIST WHERE db = 'db1';
	WHILE ProcessCount > 0 DO
		SELECT id INTO ProcessID FROM INFORMATION_SCHEMA.PROCESSLIST WHERE db = 'db1' LIMIT 1;
		SELECT id,user,host,db,command,state,info FROM INFORMATION_SCHEMA.PROCESSLIST WHERE db = 'db1' AND id = ProcessID;
		SELECT COUNT(id) INTO IsProcessRuning FROM INFORMATION_SCHEMA.PROCESSLIST WHERE db = 'db1' AND id = ProcessID;
		WHILE IsProcessRuning > 0 DO
			SELECT COUNT(id) INTO KillProcess FROM INFORMATION_SCHEMA.PROCESSLIST WHERE db = 'db1' AND id = ProcessID AND command = 'Sleep';
			IF IFNULL(KillProcess,0) = 1 THEN
				KILL ProcessID;
			END IF;
			SELECT COUNT(id) INTO IsProcessRuning FROM INFORMATION_SCHEMA.PROCESSLIST WHERE db = 'db1' AND id = ProcessID;
		END WHILE;
		SELECT COUNT(id) INTO ProcessCount FROM INFORMATION_SCHEMA.PROCESSLIST WHERE db = 'db1';	
	END WHILE;
END //

DELIMITER ;
