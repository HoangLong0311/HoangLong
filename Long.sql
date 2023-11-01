-- S11 - Nguyễn Hoàng Long - 20215081
------------------QUẢN LÍ BÀN VÀ QUẢN LÍ MENU ORDER-----------------
--<I>. QUẢN LÍ BÀN
	
-- trigger trên bảng tables, user chỉ nhập table_ID, và status mặc định là E.
CREATE OR REPLACE FUNCTION check_table_status_trigger() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IS NULL THEN
        NEW.status := 'E';
    ELSE
        CASE NEW.status
            WHEN 'E' THEN
                -- Trạng thái là 'E' (Empty)
                NEW.status := 'E';
            ELSE
                -- Trạng thái không hợp lệ
                RAISE EXCEPTION 'Invalid table status. Only "E" (Empty) or "U" (In Use) are allowed.';
        END CASE;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_table_status_trigger
BEFORE INSERT ON tables
FOR EACH ROW
EXECUTE FUNCTION check_table_status_trigger();

------

-- Trigger BEFORE UPDATE để kiểm tra điều kiện khi update giá trị order_ID hay table_ID chưa tồn tại
CREATE OR REPLACE FUNCTION table_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.table_ID is distinct from OLD.table_ID  THEN
        RAISE EXCEPTION 'Không thể sửa đổi table_ID ';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_table_update
BEFORE UPDATE ON tables
FOR EACH ROW
EXECUTE FUNCTION table_update();


-- nhập sai table_ID -> hiện thông báo 
CREATE OR REPLACE FUNCTION check_table_existence() RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tables WHERE table_ID = OLD.table_ID) THEN
        RAISE EXCEPTION 'table with ID % does not exist.', OLD.table_ID;
    END IF;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_table_existence_trigger
BEFORE DELETE ON tables
FOR EACH ROW
WHEN (OLD IS NOT NULL)
EXECUTE FUNCTION check_table_existence();

--Hiển thị trạng thái
	SELECT table_ID, status
	FROM tables;

--Tạo một view để hiển thị trạng thái của các bàn bao gồm cả thông tin của bảng
table và bảng table_order:
	CREATE VIEW table_status_view AS
	SELECT t.table_ID, d.status, taor.start_time, taor.end_time
	FROM tables t
	LEFT JOIN table_order taor ON t.table_ID = taor.table_ID;


--Xem thông tin chi tiết của các bàn theo từng hóa đơn:
	SELECT taor.desk_ID, taor.start_time, taor.end_time, o.customer_ID, o.order_time, o.pay_time, o.total_price,
       ol.food_ID, ol.quantity, ol.price
	FROM table_order taor
	JOIN orders o ON taor.order_ID = o.order_ID
	JOIN orderlines ol ON o.order_ID = ol.order_ID
	WHERE taor.table_ID = 'value..';

--Theo dõi thời gian sử dụng bàn để phân bổ:
-- Lấy thông tin chi tiết về thời gian sử dụng của mỗi bàn từ bảng table_order:

	SELECT table_ID, start_time, end_time
	FROM table_order;

--Truy vấn này trả về thông tin chi tiết về thời gian bắt đầu và kết thúc sử dụng của mỗi bàn.

-- Cập nhật các giá trị khi pay_time khác null: table_order.end_time, tables.status, customers.points    

CREATE OR REPLACE FUNCTION after_update_pay_time()
RETURNS TRIGGER AS
$$
BEGIN
    IF NEW.pay_time IS NOT NULL THEN
        -- Cập nhật bảng table_order
        UPDATE table_order
        SET end_time = CURRENT_TIMESTAMP
        WHERE order_ID = NEW.order_ID;

        -- Cập nhật bảng tables
        UPDATE tables
        SET status = 'E'
        WHERE table_ID IN (
            SELECT table_ID
            FROM table_order
            WHERE order_ID = NEW.order_ID
        );
        -- Cập nhật points (trừ điểm)
        IF NEW.total_price > 0 THEN
            -- Cập nhật customers: points = 0
            UPDATE customers
            SET points = 0
            WHERE customer_ID = (
                SELECT customer_ID
                FROM orders
                WHERE order_ID = NEW.order_ID
            );
        ELSIF NEW.total_price = 0 THEN
            -- Cập nhật customers: points = points - pre_total
            UPDATE customers
            SET points = points - NEW.pre_total
            WHERE customer_ID = (
                SELECT customer_ID
                FROM orders
                WHERE order_ID = NEW.order_ID
            );
        END IF;
        UPDATE customers
        SET points = points + NEW.total_price / 100
        WHERE customer_ID = NEW.customer_ID;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tg_after_update_pay_time
AFTER UPDATE OF pay_time ON orders
FOR EACH ROW
WHEN (OLD.pay_time IS NULL AND NEW.pay_time IS NOT NULL)
EXECUTE FUNCTION after_update_pay_time();


CREATE TRIGGER tg_after_update_pay_time
AFTER UPDATE OF pay_time ON orders
FOR EACH ROW
WHEN (OLD.pay_time IS NULL AND NEW.pay_time IS NOT NULL)
EXECUTE FUNCTION after_update_pay_time();

--<II> MENU ORDER:
-- Thêm món ăn vào menu
-- Tự động

CREATE OR REPLACE FUNCTION generate_food_id()
    RETURNS TRIGGER AS
    $$
    DECLARE
    new_food_id varchar(6);
    BEGIN
    SELECT 'FO' || LPAD(CAST(COALESCE(SUBSTRING(MAX(food_ID), 3)::integer, 0) + 1 AS varchar), 4, '0')
        INTO new_food_id
    FROM menu;
    
    NEW.food_ID := new_food_id;
    RETURN NEW;
    END;
    $$
    LANGUAGE plpgsql;

    CREATE TRIGGER auto_generate_food_id
    BEFORE INSERT ON menu
    FOR EACH ROW
    EXECUTE PROCEDURE generate_food_id();

--Hiển thị menu order trên màn hình cho khách hàng lựa chọn 

	SELECT food_name, description, unit_price
	FROM menu;

--Tạo view để hiển thị menu order dựa trên số lần món ăn đã được đặt:

	CREATE VIEW popular_menu AS
	SELECT m.food_ID, m.food_name, m.description, m.unit_price, COUNT(ol.food_ID) 
	AS total_orders
	FROM menu m
	LEFT JOIN orderlines ol ON m.food_ID = ol.food_ID
	GROUP BY m.food_ID, m.food_name, m.description, m.unit_price
	ORDER BY total_orders DESC;

--View "popular_menu" sẽ hiển thị menu order và thêm cột "total_orders" để hiển thị số lần món ăn đã được đặt.

--Tạo trigger để tự động cập nhật thông tin món ăn nổi tiếng sau khi có đơn hàng mới:

CREATE OR REPLACE FUNCTION update_popular_menu_function() RETURNS TRIGGER AS $$
BEGIN
    UPDATE popular_menu
    SET total_orders = total_orders + 1
    WHERE food_ID = NEW.food_ID;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_popular_menu_trigger
AFTER INSERT ON orderlines
FOR EACH ROW
EXECUTE FUNCTION update_popular_menu_function();


-----------------------------------------------------
