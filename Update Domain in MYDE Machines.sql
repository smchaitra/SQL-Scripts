--[MyDevice - MYDE_Machines]
--[Step 3 - Set domain fields]  v1

USE SCCMext
GO



IF OBJECT_ID('tempdb.dbo.#MYDE_Machines_Priority_Domain', 'U') IS NOT NULL
DROP TABLE #MYDE_Machines_Priority_Domain;

GO

SELECT * INTO #MYDE_Machines_Priority_Domain
  FROM (
		VALUES ('SCCM',1)
		, ('AD',2)
		, ('EPO',3)
		, ('MDATP',4)
		, ('Intune',5)
		, ('ITSM',6)	
       ) t1 (Name, SortOrder)

GO


 
DECLARE @SourceName NVARCHAR(50)



SET @SourceName = 'SCCM'

UPDATE [dbo].[MYDE_Machines]
   SET [Domain] = LOWER(SYS.Full_Domain_Name0)
      ,[Domain_Source] = @SourceName
	FROM 
	 MYDE_Machines AS M INNER JOIN 
	 SCCM_v_R_System AS SYS  ON M.SCCM_Id = SYS.ResourceID
		INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_Domain] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_Domain]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.Domain_Source = PS.Name OR M.Domain_Source IS NULL
WHERE SYS.Full_Domain_Name0 IS NOT NULL AND
CHECKSUM(M.Domain_Source, M.Domain)
	<> CHECKSUM(@SourceName, LOWER(SYS.Full_Domain_Name0))







SET @SourceName = 'AD'

UPDATE [dbo].[MYDE_Machines]
   SET [Domain] = LOWER(AD.Domain)
      ,[Domain_Source] = @SourceName
	FROM 
	 MYDE_Machines AS M INNER JOIN 
	 (SELECT 
ObjectGUID
,REPLACE(RIGHT(DistinguishedName, LEN(DistinguishedName)-CHARINDEX(',DC=',DistinguishedName)-3),',DC=','.') AS Domain
FROM  [dbo].[PBI_AD_Devices] 
WHERE DistinguishedName IS NOT NULL) AS AD  ON M.AD_Id = AD.ObjectGUID
		INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_Domain] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_Domain]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.Domain_Source = PS.Name OR M.Domain_Source IS NULL
WHERE 
CHECKSUM(M.Domain_Source, M.Domain)
	<> CHECKSUM(@SourceName, LOWER(AD.Domain))








SET @SourceName = 'MDATP'

UPDATE [dbo].[MYDE_Machines]
   SET [Domain] = LOWER(MD.Domain)
      ,[Domain_Source] = @SourceName
	FROM 
	 MYDE_Machines AS M INNER JOIN 
	 (SELECT Id,
RIGHT(ComputerDnsName, LEN(ComputerDnsName)-CHARINDEX('.',ComputerDnsName)) AS Domain
FROM [dbo].[PBI_MDATP_Machines] 
WHERE ComputerDnsName LIKE '%.%') AS MD  ON M.MDATP_Id = MD.Id
		INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_Domain] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_Domain]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.Domain_Source = PS.Name OR M.Domain_Source IS NULL
WHERE 
CHECKSUM(M.Domain_Source, M.Domain)
	<> CHECKSUM(@SourceName, LOWER(MD.Domain))







SET @SourceName = 'EPO'

UPDATE [dbo].[MYDE_Machines]
   SET [Domain] = LOWER(E.Domain)
      ,[Domain_Source] = @SourceName
	FROM 
	 MYDE_Machines AS M INNER JOIN 
	 (SELECT ParentID,
RIGHT(IPHostName, LEN(IPHostName)-CHARINDEX('.',IPHostName)) AS Domain
FROM [EPO_MODERN].[ePO_GDCEPOAP003].[dbo].[EPOComputerProperties] 
WHERE IPHostName LIKE '%.%') AS E  ON M.EPO_Id = E.ParentID
		INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_Domain] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_Domain]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.Domain_Source = PS.Name OR M.Domain_Source IS NULL
WHERE 
CHECKSUM(M.Domain_Source, M.Domain)
	<> CHECKSUM(@SourceName, LOWER(E.Domain))








SET @SourceName = 'Intune'

UPDATE [dbo].[MYDE_Machines]
   SET [Domain] = LOWER(I.Domain)
      ,[Domain_Source] = @SourceName
	  --SELECT M.Name, M.Domain, M.Domain_Source, I.Domain, @SourceName
	FROM 
	 MYDE_Machines AS M INNER JOIN 
	 (SELECT DeviceId , 
N'dir.ucb-group.com' AS Domain FROM PBI_INTUNE_ManagedDevices
WHERE AzureADDeviceId IS NOT NULL AND  MDMSystem = 'intune-prd') AS I  ON M.Intune_Id = I.DeviceId
		INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_Domain] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_Domain]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.Domain_Source = PS.Name OR M.Domain_Source IS NULL
WHERE 
CHECKSUM(M.Domain_Source, M.Domain)
	<> CHECKSUM(@SourceName, LOWER(I.Domain))