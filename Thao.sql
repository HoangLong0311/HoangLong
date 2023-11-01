-- S11 - Nguyễn Thị Ngọc Thảo - 20215138
-- QUERY QUẢN LÝ HÓA ĐƠN

-- I. Chức năng tạo hóa đơn mới:
-- 1. Chức năng trên bảng orders:
--Tự động tạo mã hóa đơn order_ID, order_time khi insert into orders
    -- Chỉ cho phép user insert giá trị customer_ID
    -- Kiểm tra điều kiện câu lệnh user nhập sai customer_ID (đối với khách hàng có thẻ thành viên) -> Thông báo lỗi
CREATE OR REPLACE FUNCTION generate_order_id()
    RETURNS TRIGGER AS
    $$
    BEGIN
        -- Kiểm tra giá trị customer_ID (đối với khách hàng có thẻ thành viên)
        IF NEW.customer_ID IS NOT NULL THEN
            -- Kiểm tra sự tồn tại của customer_ID trong bảng customers
            IF NOT EXISTS (SELECT 1 FROM customers WHERE customer_ID = NEW.customer_ID) THEN
                RAISE EXCEPTION 'Mã khách hàng customer_ID không tồn tại trong hệ thống!';
            END IF;
        END IF;

        -- Tạo new_order_id
        NEW.order_ID := (
            SELECT 'OR' || LPAD(CAST(COALESCE(SUBSTRING(MAX(order_ID), 3)::integer, 0) + 1 AS varchar), 4, '0')
            FROM orders
        );
        NEW.order_time := CURRENT_TIMESTAMP;
        RETURN NEW;
    END;
    $$
    LANGUAGE plpgsql;

CREATE TRIGGER auto_generate_order_id
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE PROCEDURE generate_order_id();
    
-----------------------------------Test dữ liệu----------------------------------------
    insert into orders(customer_ID) values(null);
    -- Một số lệnh thực thi khác:
    delete from orders where customer_ID is NULL;
    drop trigger auto_generate_order_id on orders;


-- Update 
CREATE OR REPLACE FUNCTION update_orders()
    RETURNS TRIGGER AS
    $$
    BEGIN
        IF NEW.order_ID is distinct from OLD.order_ID THEN 
            RAISE EXCEPTION 'Không cập nhật mã hóa đơn!';
        END IF;
        -- Kiểm tra giá trị customer_ID (đối với khách hàng có thẻ thành viên)
        IF NEW.customer_ID IS NOT NULL THEN
            -- Kiểm tra sự tồn tại của customer_ID trong bảng customers
            IF NOT EXISTS (SELECT 1 FROM customers WHERE customer_ID = NEW.customer_ID) THEN
                RAISE EXCEPTION 'Mã khách hàng customer_ID không tồn tại trong hệ thống!';
            END IF;
        END IF;
        RETURN NEW;
    END;
    $$
    LANGUAGE plpgsql;

CREATE TRIGGER tg_update_orders
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE PROCEDURE update_orders();

-----------------------------Test dữ liệu-----------------
    update orders set customer_ID = 'KH0003', order_ID = 'OR0002' where order_ID = 'OR0001';    -- Thông báo lỗi
    update orders set customer_ID = 'KH0001' where order_time = '23:04:20.797273';              -- Update thành công
---------Một số lệnh thực thi khác:
    drop trigger tg_update_orders on orders;


-- Tạo trigger after để hiển thị thành công
CREATE OR REPLACE FUNCTION after_insert_update_order() RETURNS TRIGGER AS 
$$
BEGIN
    RAISE NOTICE 'Đã thêm/ cập nhật thành công!';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_after_insert_update_order
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE PROCEDURE after_insert_update_order();


-- Delete order_ID: xóa thông tin trên table_order và orderlines với order_ID = old.order_ID

DELETE from orderlines_view where order_ID = 'value' and customer_ID ='value';
DELETE from orderlines_view where order_ID = 'value';
DELETE from orderlines_view where customer_ID = 'value';
--

CREATE OR REPLACE FUNCTION delete_orders()
    RETURNS TRIGGER AS
$$
DECLARE
    orderid varchar(6);
BEGIN
    IF OLD.order_ID IS NOT NULL THEN
        -- Trường hợp có order_ID
        DELETE FROM table_order WHERE order_ID = OLD.order_ID;  
        DELETE FROM orderlines_view WHERE order_ID = OLD.order_ID;
    ELSIF OLD.customer_ID IS NOT NULL THEN
        -- Trường hợp chỉ có customer_ID
        SELECT order_ID INTO orderid FROM orders WHERE customer_ID = OLD.customer_ID;
        IF orderid IS NOT NULL THEN
            DELETE FROM table_order WHERE order_ID = orderid;
            DELETE FROM orderlines_view WHERE order_ID = orderid;
        END IF;
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_delete_orders
AFTER DELETE ON orders
FOR EACH ROW
EXECUTE PROCEDURE delete_orders();

-- 2. Chức năng chọn bàn/ xóa bàn và tự động cập nhật trạng thái bàn:
    -- Khi user insert bàn vào bảng table_order, hệ thống kiểm tra xem đã tồn tại order_ID trên orders, table_ID trên tables chưa
    -- Tiếp tục kiểm tra (order_ID, table_ID) tồn tại trên table_order chưa
        -- Nếu đã tồn tại -> hiển thị thông báo và return null
        -- Nếu chưa tồn tại -> insert vào table_order, sau khi insert thành công thì cập nhật trạng thái bàn 'U' 

------------Trigger cho INSERT----------
-- Trigger BEFORE
CREATE OR REPLACE FUNCTION before_insert_table_order() RETURNS TRIGGER AS 
$$
BEGIN
    -- Kiểm tra xem đã tồn tại order_ID trên bảng orders
    IF NOT EXISTS (SELECT 1 FROM orders WHERE order_ID = NEW.order_ID) THEN
        RAISE EXCEPTION 'Không tồn tại order_ID %', NEW.order_ID;
    END IF;

    -- Kiểm tra xem đã tồn tại table_ID trên bảng tables
    IF NOT EXISTS (SELECT 1 FROM tables WHERE table_ID = NEW.table_ID) THEN
        RAISE EXCEPTION 'Không tồn tại table_ID %', NEW.table_ID;
    END IF;

    IF NEW.start_time IS NOT NULL OR NEW.end_time IS NOT NULL THEN
        RAISE EXCEPTION 'Không được phép nhập thời gian start_time và end_time!';
    END IF;

    -- Kiểm tra xem (order_ID, table_ID) đã tồn tại trên bảng table_order chưa
    IF EXISTS (SELECT 1 FROM table_order WHERE order_ID = NEW.order_ID AND table_ID = NEW.table_ID) THEN
        RAISE EXCEPTION 'Đã tồn tại (%, %) trên table_order!', NEW.order_ID, NEW.table_ID;
    ELSE
        RETURN NEW; 
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_before_insert_table_order
BEFORE INSERT ON table_order
FOR EACH ROW
EXECUTE PROCEDURE before_insert_table_order();

-- Trigger AFTER
CREATE OR REPLACE FUNCTION after_insert_table_order() RETURNS TRIGGER AS 
$$
BEGIN
    UPDATE tables SET status = 'U' WHERE table_ID = NEW.table_ID;
    -- Cập nhật start_time bằng current_timestamp
    UPDATE table_order SET start_time = current_timestamp WHERE order_ID = NEW.order_ID AND table_ID = NEW.table_ID;
    RAISE NOTICE 'Đã thêm thành công!';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_after_insert_table_order
AFTER INSERT ON table_order
FOR EACH ROW
EXECUTE PROCEDURE after_insert_table_order();

-----------Test dữ liệu------------
    insert into tables(table_ID, status) values (1, 'E'), (2,'E'),(3,'E');
    insert into table_order(order_ID, table_ID) values('OR0001',2);


--------Trigger BEFORE UPDATE để kiểm tra điều kiện khi update giá trị order_ID hay table_ID chưa tồn tại
CREATE OR REPLACE FUNCTION before_update_table_order()
    RETURNS TRIGGER AS
    $$
    BEGIN
        IF NEW.order_ID IS NOT NULL THEN 
            IF NOT EXISTS (SELECT 1 FROM orders WHERE order_ID = NEW.order_ID) THEN
                RAISE EXCEPTION 'Mã hóa đơn order_ID không tồn tại trong hệ thống!';
            END IF;
        END IF;
        -- Kiểm tra giá trị customer_ID (đối với khách hàng có thẻ thành viên)
        IF NEW.table_ID IS NOT NULL THEN
            -- Kiểm tra sự tồn tại của customer_ID trong bảng customers
            IF NOT EXISTS (SELECT 1 FROM tables WHERE table_ID = NEW.table_ID) THEN
                RAISE EXCEPTION 'Bàn % không tồn tại trong hệ thống!',NEW.table_ID;
            END IF;
        END IF;
        RETURN NEW;
    END;
    $$
    LANGUAGE plpgsql;

CREATE TRIGGER tg_before_update_table_order
    BEFORE UPDATE ON table_order
    FOR EACH ROW
    EXECUTE PROCEDURE before_update_table_order();

---------------DELETE---------- 

CREATE OR REPLACE FUNCTION after_delete_table_order() RETURNS TRIGGER AS 
$$
BEGIN
    UPDATE tables SET status = 'E' WHERE table_ID = OLD.table_ID;
    RAISE NOTICE 'Đã xóa thành công!';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_after_delete_table_order
    AFTER DELETE ON table_order
    FOR EACH ROW
    EXECUTE PROCEDURE after_delete_table_order();


-- 3. Chức năng chọn món ăn/ xóa món ăn, tính toán giá trị price, pre_total, total_price

-- Hàm tính pre_total và total_price (chưa cập nhật points)
CREATE OR REPLACE FUNCTION calculate_totals(order_id_input TEXT) RETURNS VOID AS 
$$
DECLARE
    pretotal BIGINT;
    totalprice BIGINT;
    temp_points BIGINT; 
BEGIN
    SELECT COALESCE(SUM(price), 0) INTO pretotal
    FROM orderlines_view
    WHERE order_ID = order_id_input;

    -- Lưu kết quả truy vấn SELECT vào biến temp_points
    SELECT points INTO temp_points
    FROM customers
    JOIN orders USING (customer_ID)
    WHERE order_ID = order_id_input;

    totalprice := pretotal - COALESCE(temp_points, 0);

    UPDATE orders
    SET pre_total = pretotal,
        total_price = CASE WHEN totalprice >= 0 THEN totalprice ELSE 0 END
    WHERE order_ID = order_id_input;
END;
$$ LANGUAGE plpgsql;

----------------------------------
-- Tạo view
CREATE VIEW orderlines_view AS
SELECT o.order_ID, o.food_ID, m.food_name, o.quantity, m.unit_price AS unit_price, m.unit_price * o.quantity AS price
FROM orderlines o
JOIN menu m ON o.food_ID = m.food_ID;

-- Tạo INSTEAD OF INSERT OR UPDATE trigger
CREATE OR REPLACE FUNCTION check_insert_update_orderlines() RETURNS TRIGGER AS 
$$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM orders WHERE order_ID = NEW.order_ID) THEN
        RAISE EXCEPTION 'Order_ID không tồn tại';
    ELSIF NOT EXISTS (SELECT 1 FROM menu WHERE food_ID = NEW.food_ID) THEN
        RAISE EXCEPTION 'Food_ID không tồn tại';
    ELSE
        IF EXISTS (SELECT 1 FROM orderlines WHERE order_ID = NEW.order_ID AND food_ID = NEW.food_ID) THEN
            UPDATE orderlines SET quantity = NEW.quantity, price = (SELECT unit_price * NEW.quantity FROM menu WHERE food_ID = NEW.food_ID) WHERE order_ID = NEW.order_ID AND food_ID = NEW.food_ID;
        ELSE
            INSERT INTO orderlines (order_ID, food_ID, quantity, price) VALUES (NEW.order_ID, NEW.food_ID, NEW.quantity, (SELECT unit_price * NEW.quantity FROM menu WHERE food_ID = NEW.food_ID));
        END IF;
        PERFORM calculate_totals(NEW.order_ID);
        RAISE NOTICE 'Thành công!';
    END IF;
    RETURN NULL;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '%', SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_check_insert_update_orderlines
INSTEAD OF INSERT OR UPDATE ON orderlines_view
FOR EACH ROW
EXECUTE PROCEDURE check_insert_update_orderlines();

-----------------------------------------
-- DELETE trên orderlines_view: 
DELETE from orderlines_view where order_ID = 'value' and food_ID ='value';
DELETE from orderlines_view where order_ID = 'value';
DELETE from orderlines_view where food_ID ='value';

------------
CREATE OR REPLACE FUNCTION after_delete_orderlines_view()
    RETURNS TRIGGER AS
$$
DECLARE
    orderid varchar(6);
BEGIN
    IF OLD.order_ID IS NOT NULL AND OLD.food_ID IS NOT NULL THEN
        -- Trường hợp cả order_ID và food_ID đều có
        DELETE FROM orderlines WHERE order_ID = OLD.order_ID AND food_ID = OLD.food_ID;
        PERFORM calculate_totals(OLD.order_ID);
    ELSIF OLD.order_ID IS NOT NULL THEN
        -- Trường hợp chỉ có order_ID
        DELETE FROM orderlines WHERE order_ID = OLD.order_ID;
        PERFORM calculate_totals(OLD.order_ID);
    ELSIF OLD.food_ID IS NOT NULL THEN
        -- Trường hợp chỉ có food_ID
        FOR orderid IN (SELECT DISTINCT order_ID FROM orderlines WHERE food_ID = OLD.food_ID) LOOP
            DELETE FROM orderlines WHERE order_ID = order_id;
            PERFORM calculate_totals(orderid);
        END LOOP;
    END IF;
    RAISE NOTICE 'Đã xóa thành công!';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_after_delete_orderlines_view
INSTEAD OF DELETE ON orderlines_view
FOR EACH ROW
EXECUTE PROCEDURE after_delete_orderlines_view();


----------------------------------
CREATE OR REPLACE FUNCTION check_insert_update_orderlines() RETURNS TRIGGER AS 
$$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM orders WHERE order_ID = NEW.order_ID) THEN
        RAISE EXCEPTION 'Order_ID không tồn tại';
    ELSIF NOT EXISTS (SELECT 1 FROM menu WHERE food_ID = NEW.food_ID) THEN
        RAISE EXCEPTION 'Food_ID không tồn tại';
    ELSE
        IF EXISTS (SELECT 1 FROM orderlines WHERE order_ID = NEW.order_ID AND food_ID = NEW.food_ID) THEN
            UPDATE orderlines SET quantity = NEW.quantity, price = (SELECT unit_price * NEW.quantity FROM menu WHERE food_ID = NEW.food_ID) WHERE order_ID = NEW.order_ID AND food_ID = NEW.food_ID;
        ELSE
            INSERT INTO orderlines (order_ID, food_ID, quantity, price) VALUES (NEW.order_ID, NEW.food_ID, NEW.quantity, (SELECT unit_price * NEW.quantity FROM menu WHERE food_ID = NEW.food_ID));
            UPDATE popular_menu
                SET total_orders = total_orders + 1
                WHERE food_ID = NEW.food_ID;
        END IF;
        PERFORM calculate_totals(NEW.order_ID);
        RAISE NOTICE 'Thành công!';
    END IF;
    RETURN NULL;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '%', SQLERRM;
        RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_check_insert_update_orderlines
INSTEAD OF INSERT OR UPDATE ON orderlines_view
FOR EACH ROW
EXECUTE PROCEDURE check_insert_update_orderlines();