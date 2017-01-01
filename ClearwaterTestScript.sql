----------------------------------
--Created RSutcliffe
--Test Script for Complete Package
SET SERVEROUTPUT ON
BEGIN
  DBMS_OUTPUT.PUT_LINE('RUNNING TESTING SCRIPT');
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Confirm Trigger fires after INSERT on ORDER_LINE table');
END;
/
--TRIGGER 1 TEST
SELECT inv.INV_ID, inv.INV_QOH as OLD_INV_QOH
FROM CLEARWATER.INVENTORY inv
WHERE inv.INV_ID = 26;

BEGIN
  DBMS_OUTPUT.PUT_LINE('Placing order for 30..');
END;
/
--test creating an order line for 25 items
INSERT INTO CLEARWATER.ORDER_LINE 
VALUES (6,26, 30);
--just for testing repeatability
DELETE FROM CLEARWATER.ORDER_LINE
WHERE O_ID = 6 AND INV_ID = 26;

SELECT inv.INV_ID, inv.INV_QOH as NEW_INV_QOH
FROM CLEARWATER.INVENTORY inv
WHERE inv.INV_ID = 26;

--TRIGGER 2
BEGIN
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Confirm Trigger fires if UPDATE on ORDER_LINE table');
END;
/
SELECT inv.INV_ID, inv.INV_QOH as OLD_INV_QOH
FROM CLEARWATER.INVENTORY inv
WHERE inv.INV_ID = 7;

BEGIN
  DBMS_OUTPUT.PUT_LINE('Updating order to 5..');
END;
/
--test updating an order line from 3 to 5 items
UPDATE CLEARWATER.ORDER_LINE 
SET  OL_QUANTITY = 5
WHERE O_ID = 6 AND INV_ID = 7;

SELECT inv.INV_ID, inv.INV_QOH as NEW_INV_QOH
FROM CLEARWATER.INVENTORY inv
WHERE inv.INV_ID = 7;

--TRIGGER 3
BEGIN
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Confirm Trigger fires if UPDATE on SHIPMENT_LINE table:
            Date Recieved Populated');
END;
/

SELECT inv.INV_ID, inv.INV_QOH as OLD_INV_QOH
FROM CLEARWATER.INVENTORY inv
WHERE inv.INV_ID = 2;
             
BEGIN
  DBMS_OUTPUT.PUT_LINE('Adding Received Date to SHIMENT_LINE 
            new QOH should jump 25..');
END;
/

UPDATE CLEARWATER.SHIPMENT_LINE
SET SL_DATE_RECEIVED = SYSDATE
WHERE SHIP_ID = 2 AND INV_ID = 2;

SELECT inv.INV_ID, inv.INV_QOH as NEW_INV_QOH
FROM CLEARWATER.INVENTORY inv
WHERE inv.INV_ID = 2;

--TRIGGER 4
BEGIN
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Confirm Trigger fires if UPDATE on SHIPMENT_LINE table: 
            Quantity Change');
END;
/

SELECT inv.INV_ID, inv.INV_QOH as OLD_INV_QOH
FROM CLEARWATER.INVENTORY inv
WHERE inv.INV_ID = 2;
             
BEGIN
  DBMS_OUTPUT.PUT_LINE('Adjusting Quantity recieved in SHIMENT_LINE 
            new QOH should drop by 5..');
END;
/

UPDATE CLEARWATER.SHIPMENT_LINE
SET SL_QUANTITY = 20
WHERE SHIP_ID = 2 AND INV_ID = 2;

SELECT inv.INV_ID, inv.INV_QOH as NEW_INV_QOH
FROM CLEARWATER.INVENTORY inv
WHERE inv.INV_ID = 2;

--TRIGGER END

----------------------------------------------
--PACKAGE FUNCTION TEST
BEGIN
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Confirm function CALC_ORDER_TOTAL returns total 
            of an orders items');
END;
/
--does not require a PLSQL statement
SELECT DISTINCT CLEARWATER.inv_ctl_pkg.CALC_ORDER_TOTAL(5)
FROM CLEARWATER.ORDER_LINE;

--TEST PROCEDURE ORDER_PLACED
BEGIN
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Confirm ORDER_PLACED procedures work');
END;
/

EXECUTE CLEARWATER.inv_ctl_pkg.ORDER_PLACED(1);
EXECUTE CLEARWATER.inv_ctl_pkg.ORDER_PLACED('Graham', 'Neal');

SELECT ord.O_ID, ord.O_DATE 
FROM CLEARWATER.ORDERS ord;

--TEST PROCEDURE inventory_ordered for new OrderLines
BEGIN
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Confirm INVENTORY_ORDERED and 
          CHANGED_MY_MIND procedures work');
END;
/

--get last created ORDER to execute procedure on
DECLARE
  l_max INT;
BEGIN
    SELECT DISTINCT MAX(O_ID)
    INTO l_max
    FROM CLEARWATER.ORDERS;
   
  CLEARWATER.inv_ctl_pkg.INVENTORY_ORDERED( l_max, 1, 1);
  DBMS_OUTPUT.PUT('Made Order of 1 Item');
END; 
/

--show newly created record
SELECT * FROM CLEARWATER.ORDER_LINE
WHERE O_ID = (SELECT MAX(O_ID) FROM CLEARWATER.ORDER_LINE);

--update the inventory for the orderline
DECLARE
  l_oid INT;
  l_invid INT;
BEGIN
  SELECT DISTINCT ol.O_ID, ol.INV_ID
  INTO l_oid, l_invid 
  FROM CLEARWATER.ORDER_LINE ol
  WHERE ol.O_ID = (
    SELECT MAX(O_ID)
    FROM CLEARWATER.ORDERS)
  AND ol.INV_ID = 1;
   
  CLEARWATER.inv_ctl_pkg.CHANGED_MY_MIND( l_oid, l_invid, 2);
  DBMS_OUTPUT.PUT('Changed Order to 2 Items');
END; 
BEGIN
  DBMS_OUTPUT.PUT_LINE('-------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Confirm SHIPMENT_RECEIVED and triggers work');
END;
--confirm shipment recieved works as well as triggers
EXECUTE CLEARWATER.inv_ctl_pkg.SHIPMENT_RECEIVED(3,5,SYSDATE);
--change quantity from 200 - 150
EXECUTE CLEARWATER.inv_ctl_pkg.SHIPMENT_RECEIVED(3,5, 150);
--change quantity from 200 - 150
EXECUTE CLEARWATER.inv_ctl_pkg.SHIPMENT_RECEIVED(3,5, SYSDATE, 150);

--should be 150
SELECT * FROM 
CLEARWATER.INVENTORY
WHERE INV_ID = 5;

BEGIN
  DBMS_OUTPUT.PUT_LINE('Inventory should now be 150');
END;
