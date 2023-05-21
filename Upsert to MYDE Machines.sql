--[MyDevice - MYDE_Machines]
--[Step 1 - Populate Machines]  v6.2

USE SCCMext
GO

DROP TABLE IF EXISTS #Machines
GO


CREATE TABLE [#Machines] (
	[Id] INT IDENTITY(1, 1) PRIMARY KEY
	,[Name] NVARCHAR(128) NULL
	,[LastSeen_Source] NVARCHAR(32) NOT NULL
	,[LastSeen] DATETIME2(0) NULL
	,[SourceId] NVARCHAR(255) NULL
	) ON [PRIMARY]
GO


INSERT INTO #Machines (
	Name
	,LastSeen_Source
	,LastSeen
	,SourceId
	)
SELECT DISTINCT CI.[Name]
	,'SCCM' AS [LastSeen_Source]
	,LastActiveTime AS [LastSeen]
	,CONVERT(NVARCHAR(255), CI.MachineID) AS SourceId
FROM SCCM.CM_S02.dbo.vSMS_CombinedDeviceResources AS CI
WHERE LastActiveTime IS NOT NULL

PRINT ('SCCM machines detected')


INSERT INTO #Machines (
	Name
	,LastSeen_Source
	,LastSeen
	,SourceId
	)
SELECT DISTINCT A.Name
	,'AD' AS [LastSeen_Source]
	,A.LastLogonDate
	,A.ObjectGUID
FROM PBI_AD_Devices AS A

PRINT ('AD machines detected')


INSERT INTO #Machines (
	Name
	,LastSeen_Source
	,LastSeen
	,SourceId
	)
SELECT DISTINCT CASE 
		WHEN D.Manufacturer = 'Apple'
			THEN ISNULL(D.SerialNumber, M.DeviceName)
		ELSE M.DeviceName
		END AS 'DeviceName'
	,'MDATP' AS [LastSeen_Source]
	,M.LastSeen
	,M.Id
FROM PBI_MDATP_Machines AS M
LEFT JOIN intune.ManagedDevice AS D ON M.AADDeviceId = D.AzureADDeviceId
	AND M.AADDeviceId IS NOT NULL
WHERE M.LastSeen IS NOT NULL
	AND M.DeviceName IS NOT NULL
	AND M.DeviceName <> ''
	AND M.DeviceName NOT LIKE '%MSBROWSE%'

PRINT ('MDATP machines detected')


INSERT INTO #Machines (
	Name
	,LastSeen_Source
	,LastSeen
	,SourceId
	)
SELECT NodeName
	,'EPO' AS [LastSeen_Source]
	,LastUpdate
	,CONVERT(NVARCHAR(255), EPO.AutoID)
FROM PBI_EPO_LeafNode AS EPO
WHERE lastupdate IS NOT NULL

PRINT ('EPO machines detected')


INSERT INTO #Machines (
	Name
	,LastSeen_Source
	,LastSeen
	,SourceId
	)
SELECT DISTINCT SerialNumber
	,'Intune' AS [LastSeen_Source]
	,LastSeen
	,DeviceId
FROM PBI_INTUNE_ManagedDevices AS I
WHERE (
		MDMSystem = 'intune-prd'
		OR MDMSystem = 'ipat-prd'
		)
	AND I.Manufacturer = 'Apple'
	AND LastSeen IS NOT NULL

PRINT ('Intune mobile devices detected')


INSERT INTO #Machines (
	Name
	,LastSeen_Source
	,LastSeen
	,SourceId
	)
SELECT DISTINCT [Name]
	,'ITSM'
	,[InstallationDate]
	,[ReconciliationIdentity]
FROM [dbo].[HELIX_DeployedServers]

PRINT ('Helix deployed servers detected')


INSERT INTO #Machines (
	Name
	,LastSeen_Source
	,LastSeen
	,SourceId
	)
SELECT DISTINCT Name
	,'ITSM' AS [LastSeen_Source]
	,CONVERT(DATETIME2(0), dateadd(ss, Create_Date, '19700101')) AS 'LastSeen'
	,CONVERT(NVARCHAR(255), ReconciliationIdentity) AS 'SourceId'
FROM [ITSM_DMSO_Machines]

PRINT ('Helix DMSO machines detected')


INSERT INTO #Machines (
	Name
	,LastSeen_Source
	,LastSeen
	,SourceId
	)
SELECT DISTINCT Name
	,'ITSM' AS [LastSeen_Source]
	,CONVERT(DATETIME2(0), dateadd(ss, Create_Date, '19700101')) AS 'LastSeen'
	,CONVERT(NVARCHAR(255), ReconciliationIdentity) AS 'SourceId'
FROM [ITSM_ES_Machines]

PRINT ('Helix ES machines detected')
GO


DELETE
FROM #Machines
WHERE (
		Name IS NULL
		OR Name = ''
		OR [Name] = 'Unknown'
		)

PRINT ('Clean up machines #1')
GO


WITH Machines
AS (
	SELECT *
		,ROW_NUMBER() OVER (
			PARTITION BY [Name]
			,[LastSeen_Source] ORDER BY CAST(ISNULL([LastSeen], '1980-01-01') AS DATETIME2(0)) DESC
			) AS rown
	FROM #Machines
	)
DELETE
FROM #Machines
WHERE EXISTS (
		SELECT 1
		FROM Machines
		WHERE Id = #Machines.Id
			AND rown > 1
		)

PRINT ('Clean up machines #2 : Duplicates by Name and LastSeen_Source')
GO


INSERT INTO [dbo].[MYDE_Machines] ([Name])
SELECT DISTINCT [Name]
FROM #Machines AS SRC
WHERE (
		NOT EXISTS (
			SELECT [Name]
			FROM MYDE_Machines
			WHERE ([Name] = SRC.[Name])
			)
		)

PRINT ('Insert missing machine names')
GO


DELETE
FROM [dbo].[MYDE_Machines]
WHERE NOT EXISTS (
		SELECT 1
		FROM #Machines
		WHERE [Name] = [dbo].[MYDE_Machines].[Name]
		)

PRINT ('Remove out of scope machine names')
GO


UPDATE dbo.MYDE_Machines
SET LastSeen = TM.LastSeen
	,LastSeen_Source = TM.LastSeen_Source
FROM dbo.MYDE_Machines AS M
INNER JOIN (
	SELECT *
		,ROW_NUMBER() OVER (
			PARTITION BY [Name] ORDER BY [LastSeen] DESC
				,LastSeen_Source DESC
			) AS rown2
	FROM #Machines
	) AS TM ON M.Name = TM.Name
WHERE TM.rown2 = 1
	AND TM.LastSeen IS NOT NULL
	AND TM.LastSeen > ISNULL(M.LastSeen, '1980-01-01')

PRINT ('Set last seen over all resources')
GO


WITH cte_MYDE_Machines
AS (
	SELECT M.[Name]
		,CONVERT(INT, (
				SELECT TOP (1) SourceId
				FROM #Machines
				WHERE [LastSeen_Source] = 'SCCM'
					AND [Name] = M.[Name]
				)) AS SCCM_Id
		,CONVERT(NVARCHAR(50), (
				SELECT TOP (1) SourceId
				FROM #Machines
				WHERE [LastSeen_Source] = 'AD'
					AND [Name] = M.[Name]
				)) AS AD_Id
		,CONVERT(NVARCHAR(50), (
				SELECT TOP (1) SourceId
				FROM #Machines
				WHERE [LastSeen_Source] = 'Intune'
					AND [Name] = M.[Name]
				)) AS Intune_Id
		,CONVERT(NVARCHAR(50), (
				SELECT TOP (1) SourceId
				FROM #Machines
				WHERE [LastSeen_Source] = 'MDATP'
					AND [Name] = M.[Name]
				)) AS MDATP_Id
		,CONVERT(INT, (
				SELECT TOP (1) SourceId
				FROM #Machines
				WHERE [LastSeen_Source] = 'EPO'
					AND [Name] = M.[Name]
				)) AS EPO_Id
		,CONVERT(VARCHAR(50), (
				SELECT TOP (1) SourceId
				FROM #Machines
				WHERE [LastSeen_Source] = 'ITSM'
					AND [Name] = M.[Name]
				)) AS ITSM_Id
	FROM MYDE_Machines AS M
	)
UPDATE MYDE_Machines
SET MYDE_Machines.SCCM_Id = cte_MYDE_Machines.SCCM_Id
	,MYDE_Machines.AD_Id = cte_MYDE_Machines.AD_Id
	,MYDE_Machines.Intune_Id = cte_MYDE_Machines.Intune_Id
	,MYDE_Machines.MDATP_Id = cte_MYDE_Machines.MDATP_Id
	,MYDE_Machines.EPO_Id = cte_MYDE_Machines.EPO_Id
	,MYDE_Machines.ITSM_Id = cte_MYDE_Machines.ITSM_Id
FROM MYDE_Machines
LEFT OUTER JOIN cte_MYDE_Machines ON MYDE_Machines.[Name] = cte_MYDE_Machines.[Name]
WHERE CHECKSUM(MYDE_Machines.SCCM_Id, MYDE_Machines.AD_Id, MYDE_Machines.Intune_Id, MYDE_Machines.MDATP_Id, MYDE_Machines.EPO_Id, MYDE_Machines.ITSM_Id) 
	<> CHECKSUM(cte_MYDE_Machines.SCCM_Id, cte_MYDE_Machines.AD_Id, cte_MYDE_Machines.Intune_Id, cte_MYDE_Machines.MDATP_Id, cte_MYDE_Machines.EPO_Id, cte_MYDE_Machines.ITSM_Id)


PRINT ('Link machine name with resource IDs')
GO


DROP TABLE IF EXISTS #Machines
GO


DROP TABLE IF EXISTS #ITSMAssets
GO


SELECT *
INTO #ITSMAssets
FROM OPENQUERY([HELIX], 'SELECT BMC_CORE_BMC_BaseElement.Name
				,AST_Attributes.AssetLifecycleStatus
				,BMC_CORE_BMC_BaseElement.ClassId
				,BMC_CORE_BMC_BaseElement.SerialNumber				
				,BMC_CORE_BMC_BaseElement.Model
				,convert(VARCHAR(50),BMC_CORE_BMC_BaseElement.ReconciliationIdentity) AS ReconciliationIdentity
				,dateadd(ss, AST_Attributes.Create_Date, ''19700101'') AS [CreationDate]
				,dateadd(ss, AST_Attributes.InstallationDate, ''19700101'') AS InstallationDate
			FROM [ucb_dev_ar].[dbo].[BMC_CORE_BMC_BaseElement]
			LEFT OUTER JOIN [ucb_dev_ar].[dbo].[AST_Attributes] ON (BMC_CORE_BMC_BaseElement.ReconciliationIdentity = AST_Attributes.ReconciliationIdentity)
			WHERE BMC_CORE_BMC_BaseElement.DatasetId = ''BMC.ASSET''
				AND BMC_CORE_BMC_BaseElement.ClassId IN (
					''BMC_COMPUTERSYSTEM''
					,''BMC_EQUIPMENT''
					,''BMC_OPERATINGSYSTEM''
					,''OB0050568A3355c5C4UQOlgiAAxKYA''
					)')

PRINT ('ITSM Assets loaded in temp table #ITSMAssets')
GO


WITH MobileAssets
AS (
	SELECT ReconciliationIdentity
		,CreationDate
		,RIGHT(SerialNumber, 12) AS SN_Clean
	FROM #ITSMAssets
	WHERE SerialNumber IS NOT NULL
		AND LEN(SerialNumber) > 10
		AND (
			Model LIKE '%iphone%'
			OR Model LIKE '%ipad%'
			)
	)
	,TargetAssets
AS (
	SELECT *
		,ROW_NUMBER() OVER (
			PARTITION BY SN_Clean ORDER BY CreationDate DESC
				,ReconciliationIdentity
			) AS rown
	FROM MobileAssets
	)
UPDATE dbo.MYDE_Machines
SET ITSM_Id = I.ReconciliationIdentity
FROM MYDE_Machines AS M
INNER JOIN TargetAssets AS I ON M.[Name] = I.[SN_Clean]
	AND I.rown = 1
WHERE CHECKSUM(M.ITSM_Id) <> CHECKSUM(I.ReconciliationIdentity)

PRINT ('ITSM ID assigned to mobile devices')
GO


WITH MachineAssets
AS (
	SELECT [Name]
		,ReconciliationIdentity
		,CreationDate
		,InstallationDate
	FROM #ITSMAssets
	WHERE [Name] <> '1'
		AND [Name] <> 'template'
		AND [Name] <> 'test'
		AND NOT (
			Model LIKE '%iphone%'
			OR Model LIKE '%ipad%'
			)
	)
	,TargetAssets
AS (
	SELECT *
		,ROW_NUMBER() OVER (
			PARTITION BY [Name] ORDER BY CreationDate DESC
				,InstallationDate DESC
				,ReconciliationIdentity
			) AS rown
	FROM MachineAssets
	)
UPDATE dbo.MYDE_Machines
SET ITSM_Id = I.ReconciliationIdentity
FROM MYDE_Machines AS M
INNER JOIN TargetAssets AS I ON M.[Name] = I.[Name]
	AND I.rown = 1
WHERE CHECKSUM(M.ITSM_Id) <> CHECKSUM(I.ReconciliationIdentity)

PRINT ('ITSM ID assigned to machines')
GO


WITH TargetAssets
AS (
	SELECT ReconciliationIdentity
		,AssetLifecycleStatus
		,ROW_NUMBER() OVER (
			PARTITION BY ReconciliationIdentity ORDER BY CreationDate DESC
				,InstallationDate DESC
				,ReconciliationIdentity
			) AS rown
	FROM #ITSMAssets
	WHERE EXISTS (
			SELECT 1
			FROM MYDE_Machines
			WHERE ITSM_Id = #ITSMAssets.ReconciliationIdentity
			)
	)
UPDATE dbo.MYDE_Machines
SET ITSM_StatusCode = I.AssetLifecycleStatus
FROM dbo.MYDE_Machines AS M
INNER JOIN TargetAssets AS I ON M.ITSM_Id = I.ReconciliationIdentity
	AND I.rown = 1
WHERE CHECKSUM(M.ITSM_StatusCode) <> CHECKSUM(I.AssetLifecycleStatus)

PRINT ('ITSM asset status')
GO


DROP TABLE IF EXISTS #ITSMAssets
GO
