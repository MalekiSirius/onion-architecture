USE [Kama.Mefa.Azmoon]
GO

IF EXISTS(SELECT 1 FROM sys.procedures WHERE [object_id] = OBJECT_ID('req.spGetObjectionsForCartable'))
	DROP PROCEDURE req.spGetObjectionsForCartable
GO

CREATE PROCEDURE req.spGetObjectionsForCartable
	@AActionState INT, 
	@AUserPositionID UNIQUEIDENTIFIER,
	@ALastDocState TINYINT,
	@ALastSendType TINYINT,
	@ACreationDateFrom DATETIME,
	@ACreationDateTo DATETIME,
	@ALastFlowDateFrom SMALLDATETIME,
	@ALastFlowDateTo SMALLDATETIME,
	@AType TINYINT,
	@ATestType TINYINT,
	@AResult TINYINT,
	@APageSize INT,
	@APageIndex INT
WITH ENCRYPTION
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE 
		@ActionState INT = COALESCE(@AActionState, 0),
		@UserPositionID UNIQUEIDENTIFIER = @AUserPositionID,
		@LastDocState TINYINT = COALESCE(@ALastDocState, 0),
		@LastSendType TINYINT = COALESCE(@ALastSendType, 0),
		@CreationDateFrom DATETIME = DATEADD(dd, 0, DATEDIFF(dd, 0, @ACreationDateFrom)),
		@CreationDateTo DATETIME = DATEADD(dd, 0, DATEDIFF(dd, 0, @ACreationDateFrom)),
		@LastFlowDateFrom SMALLDATETIME = DATEADD(dd, 0, DATEDIFF(dd, 0, @ALastFlowDateFrom)),
		@LastFlowDateTo SMALLDATETIME = DATEADD(dd, 0, DATEDIFF(dd, 0, @ALastFlowDateTo)),
		@Type TINYINT = COALESCE(@AType, 0),
		@TestType TINYINT = COALESCE(@ATestType, 0),
		@Result TINYINT = COALESCE(@AResult, 0),
		@PageSize INT = COALESCE(@APageSize, 10),
		@PageIndex INT = COALESCE(@APageIndex, 1)
	
	IF @PageIndex = 0 
	BEGIN
		SET @pagesize = 10000000
		SET @PageIndex = 1
	END

	DECLARE @Flow TABLE(DocumentID UNIQUEIDENTIFIER)
	IF @ActionState IN (2, 3, 10)
	BEGIN
		INSERT INTO @Flow
		SELECT DISTINCT DocumentID 
		FROM pbl.DocumentFlow
		WHERE ToPositionID = @UserPositionID
	END

	SELECT 
		Count(*) OVER() Total, 
		obj.*,
		applicantUser.FirstName ApplicantFirstName,
		applicantUser.LastName ApplicantLastName,
		applicantUser.NationalCode ApplicantNationalCode,
		lastFromUser.FirstName + ' ' + lastFromUser.LastName LastFromUserName,
		lastToUser.FirstName + ' ' + lastToUser.LastName LastToUserName,
		lastToPosition.[Type] LastToPositionType
	FROM req._Objection obj
	LEFT JOIN org.Users applicantUser ON applicantUser.ID = obj.ApplicantUserID
	LEFT JOIN org.Users lastFromUser ON lastFromUser.ID = obj.lastFromUserID
	LEFT JOIN org.Positions lastToPosition ON lastToPosition.ID = obj.LastToPositionID
	LEFT JOIN org.Users lastToUser ON lastToUser.ID = lastToPosition.UserID
	LEFT JOIN @Flow flow ON flow.DocumentID = obj.ID
	WHERE
		obj.RemoveDate is null
		AND @ActionState IN (1, 2, 3, 10, 20)
		AND (@ActionState <> 1 OR obj.LastToPositionID = @UserPositionID)
		AND (@ActionState <> 2 OR (obj.LastToPositionID <> @UserPositionID AND flow.DocumentID IS NOT NULL))
		AND (@ActionState <> 3 OR flow.DocumentID IS NOT NULL AND obj.LastDocState = 100)
		AND (@ActionState <> 10 OR flow.DocumentID IS NOT NULL) 
		AND (@LastDocState < 1 OR obj.LastDocState = @LastDocState)
		AND (@LastSendType < 1 OR obj.LastSendType = @LastSendType)
		AND (@CreationDateFrom IS NULL OR DATEADD(dd, 0, DATEDIFF(dd, 0, obj.CreationDate)) >= @CreationDateFrom)
		AND (@CreationDateTo IS NULL OR DATEADD(dd, 0, DATEDIFF(dd, 0, obj.CreationDate)) <= @CreationDateTo)
		AND (@LastFlowDateFrom IS NULL OR DATEADD(dd, 0, DATEDIFF(dd, 0, obj.LastFlowDate)) >= @LastFlowDateFrom)
		AND (@LastFlowDateTo IS NULL OR DATEADD(dd, 0, DATEDIFF(dd, 0, obj.LastFlowDate)) <= @LastFlowDateTo)
		AND (@Type < 1 OR obj.[Type] = @Type)
	Order By obj.LastFlowDate
	OFFSET ((@PageIndex - 1) * @PageSize) ROWS FETCH NEXT @PageSize ROWS ONLY;

	
	RETURN @@ROWCOUNT
END