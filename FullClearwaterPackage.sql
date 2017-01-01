SET SERVEROUTPUT ON 
--------------------------------------------------
--CREATE SEQUENCE FOR ORDERS
DROP SEQUENCE CLEARWATER.o_id_seq;
CREATE SEQUENCE CLEARWATER.o_id_seq 
 START WITH     50
 INCREMENT BY   1
 MAXVALUE 600
 NOCACHE
 NOCYCLE;
--------------------------------------------------
 --CREATE TRIGGER 1: UPDATE INVENTORY FROM SALE 
CREATE OR REPLACE TRIGGER inv_update_from_sale
AFTER INSERT
   ON CLEARWATER.ORDER_LINE
   FOR EACH ROW
  
DECLARE
   -- variable declarations
  price DECIMAL(8,2);
  total DECIMAL(8,2);
  new_qoh INT;
  color VARCHAR2(20);
  item_desc VARCHAR2(30);
BEGIN 

  UPDATE CLEARWATER.INVENTORY inv 
  SET inv.INV_QOH = inv.INV_QOH - :new.OL_QUANTITY
  WHERE inv.INV_ID = :new.INV_ID;
  
  --user implicit cursor to get price total and new quantity
  SELECT inv.INV_PRICE, inv.INV_QOH, 
    inv.COLOR, itm.ITEM_DESC 
  INTO price, new_qoh, color, item_desc
  FROM CLEARWATER.ORDER_LINE ol
  INNER JOIN CLEARWATER.INVENTORY inv
  ON ol.INV_ID = inv.INV_ID
  INNER JOIN CLEARWATER.ITEM itm
  ON itm.ITEM_ID = inv.ITEM_ID
  WHERE inv.INV_ID = :new.INV_ID AND ol.O_ID = :new.O_ID;
  
  total := price * :new.OL_QUANTITY;
  DBMS_OUTPUT.PUT_LINE('The total for order ' || :new.O_ID || ' is ' || TO_CHAR(total, '$9,999.99'));
  
  IF new_qoh < 0 THEN
    DBMS_OUTPUT.PUT_LINE('We need to get some more ' || color || '  '  || item_desc || 's.');
  END IF;
END;
/
--------------------------------------------------
--CREATE TRIGGER 2: ADJUST INVENTORY FROM UPDATE
--adjust inventory if quantity of inventory in an order is changed
CREATE OR REPLACE TRIGGER inv_update_from_salechange
AFTER UPDATE
   ON CLEARWATER.ORDER_LINE
   FOR EACH ROW
  
DECLARE 
  quantity_diff INT; --difference between original and updated value
  -- variable declarations
  price DECIMAL(8,2);
  total DECIMAL(8,2);
  new_qoh INT;
  color VARCHAR2(20);
  item_desc VARCHAR2(30);

BEGIN 
  quantity_diff := :new.ol_quantity - :old.ol_quantity;
  UPDATE CLEARWATER.INVENTORY inv 
  SET inv.INV_QOH = inv.INV_QOH - quantity_diff
  WHERE inv.INV_ID = :new.INV_ID;
   
  --user implicit cursor to get price total and new quantity
  SELECT inv.INV_PRICE, inv.INV_QOH, 
    inv.COLOR, itm.ITEM_DESC 
  INTO price, new_qoh, color, item_desc
  FROM CLEARWATER.ORDER_LINE ol
  INNER JOIN CLEARWATER.INVENTORY inv
  ON ol.INV_ID = inv.INV_ID
  INNER JOIN CLEARWATER.ITEM itm
  ON itm.ITEM_ID = inv.ITEM_ID
  WHERE inv.INV_ID = :new.INV_ID 
  AND ol.O_ID = :new.o_id;
  
  total := price * :new.OL_QUANTITY;
  DBMS_OUTPUT.PUT_LINE('The total for order ' || :new.O_ID || 
  ' has been adjusted to ' || TO_CHAR(total, '$9,999.99'));
  
  IF new_qoh < 0 THEN
    DBMS_OUTPUT.PUT_LINE('We need to get some more ' || color 
	 || '  '  || item_desc || 's.');
  END IF;

END;
/
--------------------------------------------------
--CREATE TRIGGER 3: ADJUST INVENTORY
----adjust inventory if quantity of inventory in an order is changed
CREATE OR REPLACE TRIGGER inv_update_from_rcv 
AFTER UPDATE
   ON CLEARWATER.SHIPMENT_LINE
   FOR EACH ROW
  
DECLARE 
  -- variable declarations
 
BEGIN 
  IF :old.sl_date_received IS NULL
    AND :new.sl_date_received IS NOT NULL THEN
    UPDATE CLEARWATER.INVENTORY inv 
    SET inv.INV_QOH = inv.INV_QOH + :new.sl_quantity
    WHERE inv.INV_ID = :new.INV_ID;
  END IF; 
  DBMS_OUTPUT.PUT_LINE('Inventory has been updated with shipment');
  
END;
/
--------------------------------------------------
--CREATE TRIGGER 4: ADJUST INVENTORY
--trigger fires after UPDATE on SHIMENT_LINE.SL_QUANTITY. 
--If the :OLD SL_DATE_RECIEVED value IS NOT NULL, increase/decrease
CREATE OR REPLACE TRIGGER inv_update_from_rcvchange  
AFTER UPDATE
   ON CLEARWATER.SHIPMENT_LINE
   FOR EACH ROW
  
DECLARE 
  -- variable declarations
   l_quantityChange INT;
   
BEGIN 
  l_quantityChange := :new.sl_quantity - :old.sl_quantity;
  IF :old.SL_DATE_RECEIVED IS NOT NULL THEN 
    UPDATE CLEARWATER.INVENTORY inv 
    SET INV_QOH = INV_QOH + l_quantityChange
    WHERE inv.INV_ID = :new.INV_ID;
    
    DBMS_OUTPUT.PUT_LINE('Revised inventory item quantity based on revised quantity recieved');
  END IF;  
END;
/
--------------------------------------------------
--CREATE PACKAGE
--inventory control package
--https://docs.oracle.com/database/121/LNPLS/packages.htm#LNPLS00901
CREATE OR REPLACE PACKAGE CLEARWATER.inv_ctl_pkg AS
   FUNCTION calc_order_total(o_id_in IN NUMBER) RETURN NUMBER;
   PROCEDURE ORDER_PLACED(c_id_in IN INTEGER);
   PROCEDURE ORDER_PLACED(c_last_in IN VARCHAR2, c_first_in IN VARCHAR2);
   PROCEDURE inventory_ordered(o_id_in INTEGER, inv_id_in INTEGER, 
          quantity_in INTEGER);
   PROCEDURE changed_my_mind(o_id_in INTEGER, inv_id_in INTEGER, 
          newquantity_in INTEGER);
   PROCEDURE SHIPMENT_RECEIVED(ship_id_in INTEGER, 
        inv_id_in INTEGER, curdate_in DATE);
   PROCEDURE SHIPMENT_RECEIVED(ship_id_in INTEGER, 
        inv_id_in INTEGER, curdate_in DATE, newquantity_in INTEGER);
   PROCEDURE SHIPMENT_RECEIVED(ship_id_in INTEGER, 
        inv_id_in INTEGER, newquantity_in INTEGER);       
END;
/

CREATE OR REPLACE PACKAGE BODY CLEARWATER.inv_ctl_pkg AS --body
   
  FUNCTION CALC_ORDER_TOTAL(o_id_in IN NUMBER)
  --STEP 6A)function CALC_ORDER_TOTAL(o_id) returns total $$ for an order. 
     RETURN NUMBER
  IS
    l_orderTotal NUMBER(12,2);
  BEGIN
    SELECT SUM(ol.INV_ID * inv.INV_PRICE) as total
    INTO l_orderTotal
    FROM CLEARWATER.INVENTORY inv
    INNER JOIN CLEARWATER.ORDER_LINE ol
    ON ol.INV_ID = inv.INV_ID
    WHERE ol.O_ID = o_id_in
    GROUP BY ol.O_ID;
    RETURN l_orderTotal;
  END CALC_ORDER_TOTAL;

----------------------------------------------------------  
  --6b)	ORDER PLACED PROCEDURE
  --Provide Customer ID
PROCEDURE ORDER_PLACED(c_id_in IN INTEGER)
IS
--declare variables here
BEGIN
--we assume creditcard payment and internet transaction
  INSERT INTO CLEARWATER.ORDERS 
  (O_ID, O_DATE, O_METHPMT, C_ID, OS_ID)
  VALUES (CLEARWATER.o_id_seq.NEXTVAL, SYSDATE, 'CC', c_id_in, 6);
 END;
 --Provide Customer First, Last Name
PROCEDURE ORDER_PLACED(c_last_in VARCHAR2, c_first_in IN VARCHAR2)
IS
l_cid INT;
BEGIN
 SELECT cus.C_ID
 INTO l_cid
 FROM CLEARWATER.CUSTOMER cus
 WHERE C_LAST = c_last_in AND
 C_FIRST = c_first_in;
 
 INSERT INTO CLEARWATER.ORDERS 
 (O_ID, O_DATE, O_METHPMT, C_ID, OS_ID)
 VALUES (CLEARWATER.o_id_seq.NEXTVAL, SYSDATE, 'CC', l_cid, 6);
 
END;

----------------------------------------------------------  
  --6c)	INVENTORY_ORDERED for INSERTing new order_lines

  PROCEDURE inventory_ordered(o_id_in INTEGER, inv_id_in INTEGER, 
          quantity_in INTEGER)
  IS
  BEGIN
    INSERT INTO CLEARWATER.ORDER_LINE
    (O_ID,INV_ID, OL_QUANTITY)
    VALUES (o_id_in, inv_id_in, quantity_in);
  END;
--------------------------------------------------------------
  --6d)	procedure called CHANGED_MY_MIND, for updating order_lines
  PROCEDURE changed_my_mind(o_id_in INTEGER, inv_id_in INTEGER, 
          newquantity_in INTEGER)
  IS
  BEGIN
    UPDATE CLEARWATER.ORDER_LINE
    SET OL_QUANTITY = newquantity_in
    WHERE O_ID = o_id_in AND INV_ID = inv_id_in;
  END;
----------------------------------------------------------------  
  --6e)	Overloaded procedure called SHIPMENT_RECEIVED, for updating orders
  --3 variations:
  --inventory matches expected (SHIP_ID, INV_ID, CURRDATE)
  --inventory <> match expected (SHIP_ID, INV_ID, CURRDATE, NEWQUANTITY)
  --inventory updated with new quantity (SHIP_ID, INV_ID, NEWQUANTITY)
  PROCEDURE SHIPMENT_RECEIVED(ship_id_in INTEGER, 
        inv_id_in INTEGER, curdate_in DATE)
  IS
  BEGIN
    UPDATE CLEARWATER.SHIPMENT_LINE
    SET SL_DATE_RECEIVED = curdate_in
    WHERE SHIP_ID = ship_id_in AND INV_ID = inv_id_in;
    DBMS_OUTPUT.PUT_LINE('info updated');
  END;
  
  --#2
  PROCEDURE SHIPMENT_RECEIVED(ship_id_in INTEGER, 
        inv_id_in INTEGER, curdate_in DATE, newquantity_in INTEGER)
  IS
  BEGIN
    UPDATE CLEARWATER.SHIPMENT_LINE
    SET SL_DATE_RECEIVED = curdate_in, SL_QUANTITY = newquantity_in
    WHERE SHIP_ID = ship_id_in AND INV_ID = inv_id_in;
    DBMS_OUTPUT.PUT_LINE('info updated, quantity updated');
  END;
  
  --#3
  PROCEDURE SHIPMENT_RECEIVED(ship_id_in INTEGER, 
        inv_id_in INTEGER, newquantity_in INTEGER)
  IS
  BEGIN
    UPDATE CLEARWATER.SHIPMENT_LINE
    SET SL_QUANTITY = newquantity_in
    WHERE SHIP_ID = ship_id_in AND INV_ID = inv_id_in;
    DBMS_OUTPUT.PUT_LINE('quantity updated');
  END;

END;
/
