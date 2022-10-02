IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[TblServiceTemplate]') AND type in (N'U'))
DROP TABLE [dbo].[TblServiceTemplate]
GO


INSERT [dbo].[TblJobU4IDSService] ([JobU4IDSServiceId], [ClientServiceId], [CreateOn]) 
