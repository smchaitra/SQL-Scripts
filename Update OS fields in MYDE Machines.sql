--[MyDevice - MYDE_Machines]
--[Step 2 - Set operating system fields]  v5.3

USE SCCMext
GO



DROP TABLE IF EXISTS #MYDE_Machines_Priority_OS
GO

SELECT * INTO #MYDE_Machines_Priority_OS
  FROM (
		VALUES ('SCCM',1)
		, ('AD',2)
		, ('Intune',3)
		, ('ITSM',4)
		, ('EPO',5)
		, ('MDATP',6)
       ) t1 (Name, SortOrder)
GO



DECLARE @SourceName NVARCHAR(32)

SET @SourceName = 'SCCM';

UPDATE [dbo].[MYDE_Machines]
SET [OperatingSystem] = SYS.OSCommonName
	,[OS_Version] = SYS.operatingSystemVersion0
	,[OS_ServicePack] = SYS.operatingSystemServicePac0
	,[OS_Source] = @SourceName
FROM MYDE_Machines AS M
INNER JOIN SCCM_v_R_System AS SYS ON M.SCCM_Id = SYS.ResourceID
INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_OS] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_OS]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.OS_Source = PS.Name
	OR M.OS_Source IS NULL
WHERE CHECKSUM(M.OS_Source, M.OperatingSystem, M.OS_Version, M.OS_ServicePack) <> CHECKSUM(@SourceName, SYS.OSCommonName, SYS.operatingSystemVersion0, SYS.operatingSystemServicePac0)
	AND (
		SYS.OSCommonName IS NOT NULL
		OR SYS.OSCommonName <> ''
		)

PRINT ('OS updated based on SCCM')

--DECLARE @SourceName NVARCHAR(32)
SET @SourceName = 'AD';

UPDATE [dbo].[MYDE_Machines]
SET [OperatingSystem] = AD.OperatingSystem
	,[OS_Version] = AD.OS_Version
	,[OS_ServicePack] = AD.OS_ServicePack
	,[OS_Source] = @SourceName
FROM MYDE_Machines AS M
INNER JOIN (
	SELECT A.ObjectGUID
		,ISNULL(OS.OSCommonName, A.OperatingSystem) AS 'OperatingSystem'
		,A.[OperatingSystemVersion] AS 'OS_Version'
		,A.[OperatingSystemServicePack] AS 'OS_ServicePack'
	FROM PBI_AD_Devices AS A
	LEFT OUTER JOIN OSCommonName AS OS ON A.OperatingSystem = OS.[OSADName]
	) AS AD ON M.AD_Id = AD.ObjectGUID
INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_OS] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_OS]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.OS_Source = PS.Name
	OR M.OS_Source IS NULL
WHERE CHECKSUM(M.OS_Source, M.OperatingSystem, M.OS_Version, M.OS_ServicePack) <> CHECKSUM(@SourceName, AD.OperatingSystem, AD.OS_Version, AD.OS_ServicePack)
	AND (
		AD.OperatingSystem IS NOT NULL
		OR AD.OperatingSystem <> ''
		)

PRINT ('OS updated based on AD')


SET @SourceName = 'ITSM';

WITH AssetsOS
AS (
	SELECT BR.Source_ReconciliationIdentity AS 'Id'
		,CONVERT(NVARCHAR(50), (
				CASE 
					WHEN CHARINDEX('|', OS.[Name]) > 0
						THEN RTRIM(SUBSTRING(OS.[Name], 0, CHARINDEX('|', OS.[Name], 0)))
					ELSE OS.[Name]
					END
				)) AS 'OperatingSystem'
		,CONVERT(NVARCHAR(50), OS.VersionNumber) AS 'OS_Version'
		,NULL AS 'OS_ServicePack'
		,ROW_NUMBER() OVER (
			PARTITION BY BR.Source_ReconciliationIdentity ORDER BY OS.CreateDate DESC
				,OS.ModifiedDate DESC
				,BR.Source_ReconciliationIdentity
			) rown
	FROM [HELIX].[ucb_dev_ar].[dbo].[BMC_CORE_BMC_OperatingSystem] AS OS
	INNER JOIN [HELIX].[ucb_dev_ar].[dbo].[BMC_CORE_BMC_BaseRelationship] AS BR ON OS.ReconciliationIdentity = BR.Destination_ReconciliationIden
		AND BR.DatasetId = 'BMC.ASSET'
		AND OS.DatasetId = 'BMC.ASSET'
	)
	,AssetsOS2
AS (
	SELECT Id
		,LTRIM(REPLACE(REPLACE(OperatingSystem, '®', ''), 'Microsoft', '')) AS 'OperatingSystem'
		,OS_Version
		,OS_ServicePack
	FROM AssetsOS
	WHERE rown = 1
		AND (
			OperatingSystem IS NOT NULL
			OR OperatingSystem <> ''
			)
	)
	,AssetsOS_Cleaned
AS (
	SELECT A.Id
		,ISNULL(OS.OSCommonName, A.OperatingSystem) AS 'OperatingSystem'
		,A.OS_Version
		,A.OS_ServicePack
	FROM AssetsOS2 AS A
	LEFT OUTER JOIN OSCommonName AS OS ON A.OperatingSystem = OS.[OSADName]
	)
UPDATE [dbo].[MYDE_Machines]
SET [OperatingSystem] = A.OperatingSystem
	,[OS_Version] = A.OS_Version
	,[OS_ServicePack] = A.OS_ServicePack
	,[OS_Source] = @SourceName
FROM MYDE_Machines AS M
INNER JOIN AssetsOS_Cleaned AS A ON M.ITSM_Id = A.Id
INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_OS] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_OS]
				WHERE ([Name] = @SourceName)
				)
			)
	) AS PS ON M.OS_Source = PS.[Name]
	OR M.OS_Source IS NULL
WHERE CHECKSUM(M.OS_Source, M.OperatingSystem, M.OS_Version, ISNULL(M.OS_ServicePack, '')) <> CHECKSUM(@SourceName, A.OperatingSystem, A.OS_Version, ISNULL(A.OS_ServicePack, ''))

PRINT ('OS updated based on ITSM')


SET @SourceName = 'EPO';

UPDATE [dbo].[MYDE_Machines]
SET [OperatingSystem] = E.OperatingSystem
	,[OS_Version] = E.OS_Version
	,[OS_ServicePack] = E.OS_ServicePack
	,[OS_Source] = @SourceName
FROM MYDE_Machines AS M
INNER JOIN (
	SELECT E.ParentId
		,ISNULL(OS.OSCommonName, E.OSType) AS 'OperatingSystem'
		,CONCAT (
			OSVersion
			,' ('
			,OSBuildNum
			,')'
			) AS 'OS_Version'
		,OSCsdVersion AS 'OS_ServicePack'
	FROM [EPO_MODERN].[ePO_GDCEPOAP003].[dbo].[EPOComputerProperties] AS E
	LEFT OUTER JOIN OSCommonName AS OS ON E.OSType = OS.[OSADName]
	WHERE E.OSType <> ''
	) AS E ON M.EPO_Id = E.ParentId
INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_OS] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_OS]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.OS_Source = PS.Name
	OR M.OS_Source IS NULL
WHERE CHECKSUM(M.OS_Source, M.OperatingSystem, M.OS_Version, M.OS_ServicePack) <> CHECKSUM(@SourceName, E.OperatingSystem, E.OS_Version, E.OS_ServicePack)
	AND (
		E.OperatingSystem IS NOT NULL
		OR E.OperatingSystem <> ''
		)

PRINT ('OS updated based on EPO')


SET @SourceName = 'MDATP';

UPDATE [dbo].[MYDE_Machines]
SET [OperatingSystem] = E.OperatingSystem
	,[OS_Version] = E.OS_Version
	,[OS_ServicePack] = E.OS_ServicePack
	,[OS_Source] = @SourceName
FROM MYDE_Machines AS M
INNER JOIN (
	SELECT Id
		,ISNULL(OS.OSCommonName, OSPlatform) AS 'OperatingSystem'
		,[Version] AS 'OS_Version'
		,NULL AS 'OS_ServicePack'
	FROM PBI_MDATP_Machines
	LEFT OUTER JOIN OSCommonName AS OS ON PBI_MDATP_Machines.OSPlatform = OS.[OSADName]
	WHERE LastSeen IS NOT NULL
	) AS E ON M.MDATP_Id = E.Id
INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_OS] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_OS]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.OS_Source = PS.Name
	OR M.OS_Source IS NULL
WHERE CHECKSUM(M.OS_Source, M.OperatingSystem, M.OS_Version) <> CHECKSUM(@SourceName, E.OperatingSystem, E.OS_Version)
	AND (
		E.OperatingSystem IS NOT NULL
		OR E.OperatingSystem <> ''
		)

PRINT ('OS updated based on MDATP')


SET @SourceName = 'Intune';

UPDATE [dbo].[MYDE_Machines]
SET [OperatingSystem] = I.OS_Label
	,[OS_Version] = I.OSVersion
	,[OS_ServicePack] = NULL
	,[OS_Source] = @SourceName
FROM MYDE_Machines AS M
INNER JOIN (
	SELECT *
		,CASE 
			WHEN OperatingSystem = 'iOS'				
				THEN OperatingSystem + ' ' + LEFT(OSVersion, CHARINDEX('.', OSVersion) - 1)
			WHEN OperatingSystem = 'Android'
				THEN OperatingSystem + ' ' + OSVersion
			WHEN OperatingSystem = 'macOS'
				AND OSVersion LIKE '10.%'
				THEN 'Mac OS X'
			ELSE OperatingSystem
			END AS OS_Label
	FROM PBI_INTUNE_ManagedDevices
	WHERE DeviceId IS NOT NULL
		AND OperatingSystem <> ''
	) AS I ON M.Intune_Id = I.DeviceId
INNER JOIN (
	SELECT *
	FROM [#MYDE_Machines_Priority_OS] AS P
	WHERE (
			P.SortOrder >= (
				SELECT ISNULL(SortOrder, 0) AS Expr1
				FROM [#MYDE_Machines_Priority_OS]
				WHERE (Name = @SourceName)
				)
			)
	) AS PS ON M.OS_Source = PS.Name
	OR M.OS_Source IS NULL
WHERE CHECKSUM(M.OS_Source, M.OperatingSystem, M.OS_Version) <> CHECKSUM(@SourceName, I.OS_Label, I.OSVersion)
	AND (
		I.OS_Label IS NOT NULL
		OR I.OS_Label <> ''
		)

PRINT ('OS updated based on Intune')
