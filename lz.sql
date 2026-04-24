CREATE DATABASE SalesDB;
USE SalesDB;
CREATE TABLE Customers (
    CustomerID int identity(1,1) primary key,
    FullName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) unique not null,
    RegistrationDate DATETIME default GETDATE() NOT NULL
);

create Table Orders(
    OrderID int identity(1,1) primary key,
    CustomerID int not null,
    OrderTotal FLOAT not null check (OrderTotal > 0),
    OrderDate DATETIME default GETDATE() NOT NULL,
    [Status] NVARCHAR(20) default 'Новый' not null,
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);


create DATABASE LogisticsDB;
USE LogisticsDB;

Create Table Warehouses (
    WarehouseID int identity(1,1) primary key,
    [Location] NVARCHAR(100) not null UNIQUE,
    Capacity float not null,
    ManagerContact NVARCHAR(50) not null DEFAULT 'не назначен',
    CreatedDate DATETIME default GETDATE() not null
);

create Table Shipments (
    ShipmentID int identity(1,1) primary key,
    WarehouseID int not null,
    OrderID int not null,
    TrackingCode NVARCHAR(50) unique not null,
    [Weight] FLOAT not null,
    DispatchDate DATETIME,
    [Status] NVARCHAR(20) default 'Ожидает отправки' not null,
    CONSTRAINT FK_Shipments_Warehouses FOREIGN KEY (WarehouseID) REFERENCES Warehouses(WarehouseID)
);


--==================================================================================
--процудуры + триггер


USE SalesDB;


GO
--Добавка клиентов
CREATE PROCEDURE dbo.sp_AddCustomer
    @FullName NVARCHAR(100),
    @Email NVARCHAR(100),
    @NewCustomerID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.Customers (FullName, Email)
    VALUES (@FullName, @Email);
    
    SET @NewCustomerID = SCOPE_IDENTITY();
END;
GO

GO
--новый заказ
CREATE PROCEDURE dbo.sp_AddOrder
    @CustomerID INT,
    @OrderTotal FLOAT,
    @Status NVARCHAR(20) = N'Новый',
    @NewOrderID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.Orders (CustomerID, OrderTotal, [Status])
        VALUES (@CustomerID, @OrderTotal, @Status);

        SET @NewOrderID = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
        PRINT 'Заказ ' + CAST(@NewOrderID AS NVARCHAR) + ' успешно создан!';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 
            ROLLBACK TRANSACTION;
            
        PRINT 'ОШИБКА создания заказа: ' + ERROR_MESSAGE();
        THROW; 
    END CATCH
END;
GO


GO
--триггер
CREATE TRIGGER trg_Orders_CreateShipment
ON dbo.Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE([Status]) AND NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;
    BEGIN TRY

        INSERT INTO LogisticsDB.dbo.Shipments (
            WarehouseID, 
            OrderID, 
            TrackingCode, 
            [Weight], 
            DispatchDate, 
            [Status]
        )
        SELECT 
            1 AS WarehouseID,                               
            i.OrderID,                                      
            'TRK_' + CAST(NEWID() AS NVARCHAR(36)) AS TrackingCode,
            1.0 AS [Weight],                                 
            NULL AS DispatchDate,                            
            'Ожидает отправки' AS [Status]                  
        FROM inserted i
        LEFT JOIN deleted d ON i.OrderID = d.OrderID
        WHERE 
            i.[Status] = 'Подтвержден' 
            AND (d.[Status] IS NULL OR d.[Status] <> 'Подтвержден');
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        THROW;
    END CATCH
END;
GO


USE LogisticsDB;
GO
--новый склад
CREATE PROCEDURE dbo.sp_AddWarehouse
    @Location NVARCHAR(100),
    @Capacity FLOAT,
    @ManagerContact NVARCHAR(50) = N'не назначен'
AS
    BEGIN
        INSERT INTO dbo.Warehouses ([Location], Capacity, ManagerContact)
        VALUES (@Location, @Capacity, @ManagerContact);
        
    END
GO

--===========================================================================================
-- селекты
USE SalesDB;
GO
--получение заказов по статусу
CREATE FUNCTION dbo.GetOrdersByStatus(@status NVARCHAR(20))
RETURNS TABLE
AS
RETURN 
(
    SELECT OrderID, CustomerID, OrderTotal, OrderDate, [Status] 
    FROM dbo.Orders 
    WHERE [Status] = @status
);
GO

GO
--все заказы
CREATE FUNCTION dbo.Get_AllOrders()
RETURNS TABLE
AS
RETURN 
(
    SELECT OrderID, CustomerID, OrderTotal, OrderDate, [Status]
    FROM dbo.Orders
);
GO

GO
--  получение клиентов
CREATE FUNCTION dbo.GetAllCustomers()
RETURNS TABLE
AS
RETURN 
(
    SELECT CustomerID, FullName, Email, RegistrationDate 
    FROM dbo.Customers
);
GO


USE LogisticsDB;
GO
--получение всех складов
CREATE FUNCTION dbo.GetAllWarehouses()
RETURNS TABLE
AS
RETURN 
(
    SELECT WarehouseID, [Location], Capacity, ManagerContact, CreatedDate 
    FROM dbo.Warehouses
);
GO

GO
--получение доставок по складу
CREATE FUNCTION dbo.Get_ShipmentsByWarehouse(@wid INT)
RETURNS TABLE
AS
RETURN 
(
    SELECT ShipmentID, WarehouseID, OrderID, TrackingCode, [Weight], DispatchDate, [Status]
    FROM dbo.Shipments 
    WHERE WarehouseID = @wid
);
GO

GO
--все доставки
CREATE FUNCTION dbo.Get_AllShipments()
RETURNS TABLE
AS
RETURN 
(
    SELECT ShipmentID, WarehouseID, OrderID, TrackingCode, [Weight], DispatchDate, [Status]
    FROM dbo.Shipments
);
GO


--===========================================================================================
--задания

EXEC LogisticsDB.dbo.sp_AddWarehouse 
    @Location = 'Москва', 
    @Capacity = 10000.0,
    @ManagerContact = 'Иванов Иван',
    @NewWarehouseID =  OUTPUT;

EXEC LogisticsDB.dbo.sp_AddWarehouse 
    @Location = N'Новосибирск, Склад №2', 
    @Capacity = 5500.0, 
    @ManagerContact = N'Иван Петров',
    @NewWarehouseID = @NewWarehouseID OUTPUT;


