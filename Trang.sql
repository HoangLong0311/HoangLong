-- Phần khách hàng và một vài phần của đơn hàng
-- 1. Quản lý thông tin khách hàng
-- 1.1/ Tạo khách hàng mới: Thông tin của khách hàng sẽ bao gồm customer_ID,first_name,last_name,phone,points. Lưu ý customer_ID, points sẽ tự động được tạo.
-- Nếu người dùng cố tình tạo thì sẽ in ra thông báo lỗi
--Sử dụng Trigger để tạo customer_ID tự động tạo mã lưu dưới dạng "KHxxxx", người dùng không có quyền chỉnh sửa
CREATE OR REPLACE FUNCTION generate_customer_id()
    RETURNS TRIGGER AS
    $$
    DECLARE
    new_customer_id varchar(6);
    BEGIN
    SELECT 'KH' || LPAD(CAST(COALESCE(SUBSTRING(MAX(customer_ID), 3)::integer, 0) + 1 AS varchar), 4, '0')
        INTO new_customer_id
    FROM customers;
    
    NEW.customer_ID := new_customer_id;
    RETURN NEW;
    END;
    $$
    LANGUAGE plpgsql;
CREATE TRIGGER auto_generate_customer_id
    BEFORE INSERT ON customers
    FOR EACH ROW
    EXECUTE PROCEDURE generate_customer_id();
    
    --Sử dụng Trigger hệ thống chỉ cho nhập 1 số điện thoại. Nếu số điện thoại đã tồn tại thì không thể insert into thêm vào số điện thoại đó được nữa
CREATE OR REPLACE FUNCTION check_phone()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM customers WHERE phone = NEW.phone) THEN
        RAISE EXCEPTION 'Số điện thoại đã tồn tại trong hệ thống';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER checkphone_trigger
BEFORE INSERT ON customers
FOR EACH ROW
EXECUTE FUNCTION check_phone();
-- Hàm tự động tính points bằng cách lấy total_price /100. Sau khi hóa đơn được cập nhật thành công hệ thống sẽ tự động cập nhập points vào khách hàng đó
CREATE OR REPLACE FUNCTION updatepoint()
RETURNS TRIGGER AS
$$
BEGIN
    IF NEW.pay_time IS NOT NULL THEN
        UPDATE customers
        SET points = points + NEW.total_price / 100
        WHERE customer_ID = NEW.customer_ID;
    END IF;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER point_trigger
AFTER UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION updatepoint();
--2 / Hiển thị thông tin của khách hàng cần tìm kiếm
-- 2.1/ Người dùng nhập số điện thoại thì hệ thống sẽ hiển thị các thông tin bao gồm customer_ID, first_name,last_name,phone, points. Nếu phone đó mà chưa
-- tồn tại thì hệ thống sẽ in ra là số điện thoại chưa tồn tại trong hệ thống
CREATE OR REPLACE FUNCTION get_customer_info(phone_number VARCHAR)
RETURNS TABLE (customer_ID VARCHAR(6), first_name VARCHAR, last_name VARCHAR, phone VARCHAR, points BIGINT) AS $$
BEGIN
    RETURN QUERY EXECUTE format('
        SELECT customer_ID, first_name, last_name, phone, points
        FROM customers
        WHERE phone = %L', phone_number);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Số điện thoại % chưa có trong hệ thống. Vui lòng nhập lại.', phone_number;
    END IF;
END;
$$ LANGUAGE plpgsql;
---> test:select customer_id, first_name, last_name ,phone  from get_customer_info('13555')
--2.2/Sửa thông tin khách hàng: Người dùng có thể thay đổi tất cả các thông tin ngoài trừ customer_ID nếu thay đổi customer_ID thì sẽ 
-- được in ra là 'Không thể sửa đổi customer_ID!'
CREATE OR REPLACE FUNCTION customer_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.customer_ID is distinct from OLD.customer_ID THEN
        RAISE EXCEPTION 'Không thể sửa đổi customer_ID!';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER check_customer_update
BEFORE UPDATE ON customers
FOR EACH ROW
EXECUTE FUNCTION customer_update();
--2.3/ Hiển thị tất cả khách hàng
select * from customers;
--2.4/ sắp xếp tên khách hàng theo thứ tự tên tăng dần
SELECT *
FROM customers
ORDER BY first_name ASC;
--2.5/ Tạo view cho xem  tổng hóa đơn đã mua của customers
CREATE OR REPLACE VIEW my_vieew AS
SELECT c.customer_ID, COUNT(o.order_ID), c.points AS order_counts
FROM customers c, orders o where c.customer_ID = o.customer_ID
GROUP BY c.customer_ID;
--- select * from my_vieew
----------------------------------------------------------------------------------------------------------------------
--3.1: Hiển thị toàn bộ hóa đơn
select * from orders;
--3.2.2: Xóa hóa đơn đã sẵn có
delete from orders
where order_ID=''
--3.3:Lịch sử hóa đơn
--Tìm kiếm hóa đơn muốn xem từ order_ID
 select * from orders where order_ID='$nhapvao'; -- Lệnh select không cho phép sử dụng trigger
-- Tìm kiếm hóa đơn dựa theo ngày tháng năm đặt hàng
select * from orders where date(order_time)='nam-thang-ngay'
-- Hiển thị ra ngày mà có nhiều hóa đơn nhất
SELECT order_time::date AS order_date, COUNT(*) AS total_orders
FROM orders
GROUP BY order_time::date
ORDER BY total_orders DESC
LIMIT 1;
-- Hiển thị ra giờ mà khách hàng mua nhiều nhất
SELECT EXTRACT(HOUR FROM order_time) AS hour, COUNT(*) AS total_orders
FROM orders
GROUP BY hour
ORDER BY total_orders DESC
LIMIT 1;

-- Hiển thị ra ngày có total_price cao nhất
SELECT order_time::date AS order_date, SUM(total_price) AS total_price_sum
FROM orders
GROUP BY order_time::date
ORDER BY total_price_sum DESC
LIMIT 1;
-- Hiển thị hóa đơn theo thứ tự ngày mới nhất lên đầu
SELECT *
FROM orders
ORDER BY order_time::date desc;
--- Nếu sử dụng thời gian như này nó sẽ lưu luôn thời gian hiện tại và tự sắp xếp từ cũ đến mới
CREATE TABLE orders(
    order_ID VARCHAR(6) PRIMARY KEY NOT NULL,
    customer_ID VARCHAR(6) NOT NULL,
    order_time TIMESTAMP DEFAULT current_timestamp
);
-- View để hiển thị tổng quát chung tất cả những thông tin bao gồm tên khách hàng, mã khách hàng, tên món, số lượng, giá cả, thời gian đặt hàng  
CREATE OR REPLACE VIEW infor as
select o.order_id,o.customer_ID,c.first_name,c.last_name,t.table_ID,m.food_name,os.quantity,os.price,o.pre_total,o.total_price,o.order_time,o.pay_time
from orders o, table_order t,orderlines os,customers c, menu m
 where o.order_ID=t.order_ID and o.order_ID=os.order_ID and o.customer_ID = c.customer_ID and m.food_ID=os.food_ID;
