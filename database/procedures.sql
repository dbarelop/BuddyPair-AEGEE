DROP PROCEDURE IF EXISTS emparejar_estudiantes;
DROP PROCEDURE IF EXISTS emparejar;

DELIMITER $$
CREATE PROCEDURE emparejar_estudiantes(IN erasmus INT, IN peer INT) BEGIN
	INSERT INTO BUDDY_PAIR(erasmus, peer) values (erasmus, peer);
END $$

-- Procedimiento que empareja todos los estudiantes Erasmus posibles con sus respectivos tutores.
-- El criterio para realizar los emparejamientos se basa está basado en un sistema de pesos con los siguientes valores:
-- * Mismos estudios								 2 puntos
-- * Misma facultad									 1 punto
-- * Diferente facultad								-1 punto
-- * Género preferido / sin preferencia de género	 1 punto (Erasmus + tutor)
-- Se da preferencia después de aplicar estos criterios a los estudiantes que se hayan apuntado antes.
-- Se da preferencia antes de aplicar estos criterios a los tutores que menos estudiantes Erasmus asignados tienen
-- TODO: dar preferencia a miembros de AEGEE y añadir soporte para preferencia de idiomas
CREATE PROCEDURE emparejar() BEGIN
	DECLARE _done_erasmus, _done_peers BOOLEAN DEFAULT FALSE;
	DECLARE _erasmus_id, _erasmus_student_id, _erasmus_studies, _erasmus_faculty INT;
	DECLARE _erasmus_gender_preference, _erasmus_gender BOOLEAN;
	DECLARE _peer_id, _peer_erasmus_limit, _peer_erasmus_asignados, _peer_student_id, _peer_studies, _peer_faculty INT;
	DECLARE _peer_gender_preference, _peer_gender BOOLEAN;
	DECLARE _mejor_peer_id, _max_peso INT;
	DECLARE _cur_erasmus CURSOR FOR 
		SELECT ERASMUS.id, ERASMUS.gender_preference, STUDENT.id, STUDENT.gender, STUDENT.studies, STUDENT.faculty
		FROM ERASMUS 
		INNER JOIN STUDENT 
		ON ERASMUS.erasmus = STUDENT.id 
		--LEFT JOIN ERASMUS_LANGUAGE_PREFERENCE 
		--ON ERASMUS.id = ERASMUS_LANGUAGE_PREFERENCE.erasmus 
		WHERE NOT EXISTS (
			SELECT * 
			FROM BUDDY_PAIR 
			WHERE erasmus = ERASMUS.id) 
		ORDER BY register_date ASC;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET _done_erasmus := TRUE;

	DROP TABLE IF EXISTS PESOS;
	CREATE TEMPORARY TABLE PESOS(peso int default 0) 
		SELECT id AS peer_id, (SELECT COUNT(*) FROM BUDDY_PAIR WHERE peer = peer_id) AS erasmus_asignados FROM PEER WHERE (
			SELECT COUNT(*) 
			FROM BUDDY_PAIR 
			WHERE peer = PEER.id) < PEER.erasmus_limit;
	OPEN _cur_erasmus;
	erasmus_loop: LOOP
		FETCH _cur_erasmus INTO _erasmus_id, _erasmus_gender_preference, _erasmus_student_id, _erasmus_gender, _erasmus_studies, _erasmus_faculty;
		IF _done_erasmus THEN
			CLOSE _cur_erasmus;
			LEAVE erasmus_loop;
		END IF;
		BLOQUE2: BEGIN
			DECLARE _min_erasmus_asignados INT;
			DECLARE _cur_peers CURSOR FOR
				SELECT PEER.id AS peer_id, PEER.gender_preference, PEER.erasmus_limit, STUDENT.id, STUDENT.gender, STUDENT.studies, STUDENT.faculty 
				FROM PESOS
				INNER JOIN PEER 
				ON PESOS.peer_id = PEER.id
				INNER JOIN STUDENT 
				ON PEER.peer = STUDENT.id 
				--LEFT JOIN PEER_LANGUAGE_PREFERENCE 
				--ON PEER.id = PEER_LANGUAGE_PREFERENCE.peer 
				WHERE PESOS.erasmus_asignados = _min_erasmus_asignados AND PESOS.erasmus_asignados < PEER.erasmus_limit
				ORDER BY PEER.register_date ASC;
			DECLARE CONTINUE HANDLER FOR NOT FOUND SET _done_peers := TRUE;

			SELECT MIN(erasmus_asignados) INTO _min_erasmus_asignados FROM PESOS;
			OPEN _cur_peers;
			peers_loop: LOOP
				FETCH _cur_peers INTO _peer_id, _peer_gender_preference, _peer_erasmus_limit, _peer_student_id, _peer_gender, _peer_studies, _peer_faculty;
				IF _done_peers THEN
					SET _done_erasmus := FALSE;
					SET _done_peers := FALSE;
					CLOSE _cur_peers;
					LEAVE peers_loop;
				END IF;
				IF (_erasmus_studies IS NOT NULL) AND (_peer_studies IS NOT NULL) AND (_erasmus_studies = _peer_studies) THEN
					UPDATE PESOS SET peso = peso + 2 WHERE peer_id = _peer_id;
				END IF;
				IF (_erasmus_faculty IS NOT NULL) AND (_peer_faculty IS NOT NULL) AND (_erasmus_faculty = _peer_faculty) THEN
					UPDATE PESOS SET peso = peso + 1 WHERE peer_id = _peer_id;
				ELSE
					UPDATE PESOS SET peso = peso - 1 WHERE peer_id = _peer_id;
				END IF;
				-- TODO: añadir comprobación de conjuntos no disjuntos de preferencias de idiomas (no implementado)
				IF (_erasmus_gender_preference IS NULL) OR (_erasmus_gender_preference = _peer_gender_preference) THEN
					UPDATE PESOS SET peso = peso + 1 WHERE peer_id = _peer_id;
				END IF;
				IF (_peer_gender_preference IS NULL) OR (_peer_gender_preference = _erasmus_gender_preference) THEN
					UPDATE PESOS SET peso = peso + 1 WHERE peer_id = _peer_id;
				END IF;
			END LOOP peers_loop;
		END BLOQUE2;
		SELECT MAX(peso) INTO _max_peso FROM PESOS;
		SELECT peer_id INTO _mejor_peer_id FROM PESOS WHERE peso = _max_peso LIMIT 1;
		CALL emparejar_estudiantes(_erasmus_id, _mejor_peer_id);
		UPDATE PESOS SET erasmus_asignados = erasmus_asignados + 1 WHERE peer_id = _mejor_peer_id;
		UPDATE PESOS SET peso = 0;
	END LOOP erasmus_loop;
	DROP TABLE PESOS;
END $$
DELIMITER ;