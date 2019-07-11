#pragma semicolon 1
#pragma tabsize 0
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

enum PlayerData {
	
	bool:bLoad, 
	bool:bComplain, 
	bool:bViolation, 
	bool:bC, 
	bool:bMenu, 
	
	iID, 
	iBalls, 
	iRating, 
	iGrp, 
	
};
any _Players[MAXPLAYERS + 1][PlayerData];

ArrayList g_arAbuseSendInfo[MAXPLAYERS + 1];
DataPack g_dpAlertInfo[MAXPLAYERS + 1];

char g_sMap[128];

int _iBalls = 10, _iRating = 10;

StringMap g_smTickets, g_smCommands;

ArrayList g_arAbuseList, g_arRewards;

Handle g_fwdOnClientChoseReward;

public Plugin myinfo =  {
	name = "[ URS ]", 
	author = "", 
	description = "", 
	version = "", 
	url = ""
};

public void OnPluginStart() {
	
	// А зачем тут база? -_- 
	// Можно все на сайт кидать.
	ConnectDatabase();
	
	CreateForwards();
	
	LoadTranslations("core.phrases");
	LoadTranslations("urs.phrases");
	
}

#define SQLCB(%0) public void %0(Database hDatabase, DBResultSet results, const char[] szError, any data)
Database g_hDatabase;
void ConnectDatabase() {
	
	Database.Connect(ConnectCallBack, "urs");
	
}
public void ConnectCallBack(Database hDB, const char[] sError, any iData) {
	
	if (hDB == null) {
		SetFailState("Database failure: %s", sError);
		return;
	}
	
	g_hDatabase = hDB;
	
	SQL_LockDatabase(g_hDatabase);
	
	// Table `Users`
	// id
	// auth
	// name
	// balls
	// rating
	// grp - Group (0 - игрок / 1 - адм. имеющий доступ к работе с тикетами на игроков / 2 - адм. с полным доступом)
	
	// Table `Tickets`
	// id		- Ticket ID
	// cid 		- Culprit ID
	// uid 		- User ID (Sender ID)
	// sid		- Server ID
	// ticket 	- Abuse Text
	// status	- Ticket Status (0 - Рассматривается / 1 - Рассмотрен / 2 - Отклонено / 3 - Наказание применено)
	// aid 		- Admin ID
	// ptype	- Punishment Type (0 - Mute / 1 - Ban)
	// ptime	- Punishment Time	(0 - no / 1 - permament / >1 - time in sec)
	// ptext	- Punishment Text	(punishment reason in game)
	// atime	- Activation Time
	// map 		- Current Map Path
	// itime	- Current TimeStamp
	// itick	- Current TickCount
	
	// Table `Servers`
	// id 		- Server ID
	// name		- Server Name
	g_hDatabase.Query(SQL_Callback_CheckError, "CREATE TABLE IF NOT EXISTS `Users` (\
	`id` INT NOT NULL AUTO_INCREMENT, \
	`auth` VARCHAR(32) NOT NULL, \
	`name` VARCHAR(64) NOT NULL, \
	`balls` INT NOT NULL, \
	`rating` INT NOT NULL, \
	`grp` INT NOT NULL,\
	PRIMARY KEY (`id`)) \
	CHARSET=utf8 COLLATE utf8_general_ci;");
	g_hDatabase.Query(SQL_Callback_CheckError, "CREATE TABLE IF NOT EXISTS `Tickets` ( \
	`id` INT NOT NULL AUTO_INCREMENT, \
	`cid` INT NOT NULL, \
	`uid` INT NOT NULL,\
	`sid` INT NOT NULL, \
	`ticket` VARCHAR(128) NOT NULL, \
	`status` INT NOT NULL, \
	`aid` INT NOT NULL, \
	`ptype` INT NOT NULL, \
	`ptime` INT NOT NULL, \
	`ptext` VARCHAR(128) NOT NULL, \
	`atime` INT NOT NULL, \
	`map` VARCHAR(128) NOT NULL, \
	`itime` INT NOT NULL, \
	`itick` INT NOT NULL, \ 
	PRIMARY KEY (`id`)) \
	CHARSET=utf8 COLLATE utf8_general_ci;");
	g_hDatabase.Query(SQL_Callback_CheckError, "CREATE TABLE IF NOT EXISTS `Servers` (\
	`id` INT NOT NULL AUTO_INCREMENT, \
	`name` VARCHAR(128) NOT NULL,\
	PRIMARY KEY (`id`)) \
	CHARSET=utf8 COLLATE utf8_general_ci;");
	
	SQL_UnlockDatabase(g_hDatabase);
	
	g_hDatabase.Query(SQL_Callback_CheckError, "SET NAMES 'utf8'");
	g_hDatabase.Query(SQL_Callback_CheckError, "SET CHARSET 'utf8'");
	
	g_hDatabase.SetCharset("utf8");
	
	if (g_sMap[0] == '\0') {
		GetMap();
	}
}
SQLCB(SQL_Callback_CheckError) {
	if (szError[0]) {
		LogError("SQL_Callback_CheckError: %s", szError);
	}
}
public void OnMapStart() {
	GetMap();
	
	LoadCommands();
	LoadAbuseList();
	LoadRewardsList();
	
	if (g_smTickets == null) {
		g_smTickets = new StringMap();
	} else {
		g_smTickets.Clear();
	}
}
void GetMap() {
	g_sMap[0] = '\0';
	if (g_hDatabase == null) { return; }
	char sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	g_hDatabase.Escape(sMap, g_sMap, 2 * strlen(sMap) + 1);
}

void LoadCommands() {
	
	if (g_smCommands) {
		g_smCommands.Clear();
	} else {
		g_smCommands = new StringMap();
	}
	
	g_smCommands.SetValue("sm_urs", 0); // 0 - console
	g_smCommands.SetValue("!urs", 1); // 1 - chat
	g_smCommands.SetValue("/urs", 1); // 1 - chat
	g_smCommands.SetValue("urs", 1); // 1 - chat
	g_smCommands.SetValue("гкы", 2); // 2 - all
	
}
void LoadAbuseList() {
	if (g_arAbuseList == null) {
		g_arAbuseList = new ArrayList(ByteCountToCells(64));
	} else {
		g_arAbuseList.Clear();
	}
	g_arAbuseList.PushString("Abuse_Cheater");
	g_arAbuseList.PushString("Abuse_Other");
}
void LoadRewardsList() {
	if (g_arRewards == null) {
		g_arRewards = new ArrayList(ByteCountToCells(64));
	} else {
		g_arRewards.Clear();
	}
	g_arRewards.PushString("Reward_Shop");
	g_arRewards.PushString("Reward_Other");
}

bool FindCommand(const char[] sCommand, int iNeededType) {
	
	int iValue;
	if (!g_smCommands.GetValue(sCommand, iValue)) {
		return false;
	}
	
	return iValue == 2 || iValue == iNeededType;
	
}
public Action OnClientCommand(int iClient, int iArgs) {
	
	char sCommand[64];
	GetCmdArg(0, sCommand, sizeof(sCommand));
	
	if (FindCommand(sCommand, 0)) {
		
		CreateURSMenu(iClient);
		
	}
	
	return Plugin_Continue;
	
}
public Action OnClientSayCommand(int iClient, const char[] sType, const char[] sArgs) {
	
	char sCommand[64];
	strcopy(sCommand, sizeof(sCommand), sArgs);
	TrimString(sCommand);
	
	if (FindCommand(sCommand, 1)) {
		
		CreateURSMenu(iClient);
		
		return Plugin_Handled;
		
	}
	
	return Plugin_Continue;
	
}

void CreateURSMenu(int iClient) {
	
	Menu hMenu = new Menu(MenuHandler_URSMenu);
	
	int iVar = 10;
	if (_Players[iClient][bLoad] == true) {
		iVar = _Players[iClient][iRating];
	}
	else {
		_Players[iClient][bMenu] = true;
		CreateAlertPanel(iClient, "AlertTitle_Attention", "AlertText_DataLoading", "");
		
		return;
	}
	
	char sBuffer[256];
	SetGlobalTransTarget(iClient);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "URS_Title", iVar); hMenu.SetTitle(sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "URS_About"); hMenu.AddItem("", sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "URS_Report"); hMenu.AddItem("", sBuffer);
	
	if (_Players[iClient][bComplain]) { iVar = ITEMDRAW_DEFAULT; }
	else { iVar = ITEMDRAW_DISABLED; }
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "URS_Complaints"); hMenu.AddItem("", sBuffer, iVar);
	
	if (_Players[iClient][bViolation]) { iVar = ITEMDRAW_DEFAULT; }
	else { iVar = ITEMDRAW_DISABLED; }
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "URS_Violations"); hMenu.AddItem("", sBuffer, iVar);
	
	if (_Players[iClient][iBalls]) { iVar = ITEMDRAW_DEFAULT; }
	else { iVar = ITEMDRAW_DISABLED; }
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "URS_Rewards"); hMenu.AddItem("", sBuffer, iVar);
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	
}
#define _MenuHandler(%0) public int %0(Menu hMenu, MenuAction iAction, int iClient, int iItem)

_MenuHandler(MenuHandler_URSMenu) {
	
	switch (iAction) {
		
		case MenuAction_Select: {
			
			switch (iItem) {
				case 0: {
					// Что такое URS?
					CreateAboutMenu(iClient);
				}
				case 1: {
					// Сообщить о нарушниии
					CreateReportAbuseMenu(iClient);
				}
				case 2: {
					// Мои жалобы на игроков
					CreateMyComplaintsMenu(iClient);
				}
				case 3: {
					// Мои нарушения
					CreateMyViolationsMenu(iClient);
				}
				case 4: {
					// Управление баллами
					CreateRewardsMenu(iClient);
				}
				default: {  }
			}
			
		}
		case MenuAction_End: {
			delete hMenu;
		}
		default: {  }
		
	}
	
}
void CreateAboutMenu(int iClient) {
	
	char sBuffer[256];
	Panel hPanel = new Panel();
	
	SetGlobalTransTarget(iClient);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "About_Title");
	hPanel.SetTitle(sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "About_Text");
	sBuffer[255] = '\0';
	hPanel.DrawText(sBuffer);
	
	hPanel.CurrentKey = 8;
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Back"); hPanel.DrawItem(sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Exit"); hPanel.DrawItem(sBuffer);
	
	hPanel.Send(iClient, MenuHandler_AboutMenu, MENU_TIME_FOREVER);
	
	LogError("TextRemaining: %i", hPanel.TextRemaining);
	
	delete hPanel;
}
_MenuHandler(MenuHandler_AboutMenu) {
	
	if (iAction == MenuAction_Select) {
		
		if (iItem == 8) {
			CreateURSMenu(iClient);
			return;
		}
		
	}
	
}

public void CreateReportAbuseMenu(int iClient) {
	
	char sUserID[5], sName[64];
	Menu hMenu = new Menu(MenuHandler_RAMenu);
	
	SetGlobalTransTarget(iClient);
	
	hMenu.SetTitle("%t", "ReportPlayers_Title");
	
	for (int i = 1; i <= MaxClients; i++) {
		// TODO i != iClient
		if (/*i != iClient &&*/IsClientInGame(i) && !IsFakeClient(i)) {
			
			GetClientName(i, sName, sizeof(sName));
			FormatEx(sUserID, sizeof(sUserID), "%i", GetClientUserId(i));
			
			hMenu.AddItem(sUserID, sName, _Players[i][bLoad] == true ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
			
		}
		
	}
	
	if (hMenu.ItemCount == 0) {
		FormatEx(sName, sizeof(sName), "%t", "Players_Empty");
		hMenu.AddItem("", sName, ITEMDRAW_DISABLED);
	}
	
	hMenu.ExitBackButton = true;
	hMenu.ExitButton = true;
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	
}
_MenuHandler(MenuHandler_RAMenu) {
	
	switch (iAction) {
		
		case MenuAction_Select: {
			
			char sUserID[5];
			int iTarget;
			hMenu.GetItem(iItem, sUserID, sizeof(sUserID));
			if (!(iTarget = GetClientOfUserId(StringToInt(sUserID)))) {
				
				if (g_dpAlertInfo[iClient]) {
					delete g_dpAlertInfo[iClient];
				}
				g_dpAlertInfo[iClient] = new DataPack();
				
				g_dpAlertInfo[iClient].WriteFunction(CreateReportAbuseMenu);
				g_dpAlertInfo[iClient].WriteString("");
				
				CreateAlertPanel(iClient, "AlertTitle_Notification", "AlertText_PlayerExited", "AlertItem_BackToPlayers");
				
				PrintToChat(iClient, "%t", "Players_NotConnected");
				
				return 0;
				
			}
			
			char sName[64];
			GetClientName(iTarget, sName, sizeof(sName));
			
			g_arAbuseSendInfo[iClient] = new ArrayList(ByteCountToCells(64));
			g_arAbuseSendInfo[iClient].Push(GetTime());
			g_arAbuseSendInfo[iClient].Push(GetGameTickCount());
			g_arAbuseSendInfo[iClient].Push(_Players[iTarget][iID]);
			g_arAbuseSendInfo[iClient].PushString(sName);
			
			CreateReportAbuseTargetMenu(iClient);
			
		}
		case MenuAction_Cancel: {
			
			if (iItem == MenuCancel_ExitBack) {
				
				CreateURSMenu(iClient);
				
			}
			
		}
		case MenuAction_End: {
			delete hMenu;
		}
		default: {  }
		
	}
	
	return 0;
	
}
void CreateReportAbuseTargetMenu(int iClient) {
	
	Menu hMenu = new Menu(MenuHandler_RATMenu);
	char sBuffer[64];
	
	SetGlobalTransTarget(iClient);
	
	hMenu.SetTitle("%t", "ReportAbuse_Title");
	
	for (int i = 0; i < g_arAbuseList.Length; i++) {
		
		g_arAbuseList.GetString(i, sBuffer, sizeof(sBuffer));
		FormatEx(sBuffer, sizeof(sBuffer), "%t", sBuffer);
		hMenu.AddItem("", sBuffer);
		
	}
	
	if (hMenu.ItemCount == 0) {
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "ReportAbuse_Empty");
		hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	}
	
	hMenu.ExitBackButton = true;
	hMenu.ExitButton = true;
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
}
_MenuHandler(MenuHandler_RATMenu) {
	
	switch (iAction) {
		
		case MenuAction_Select: {
			
			char sNull[1], sAbuseReson[64];
			hMenu.GetItem(iItem, sNull, sizeof(sNull), _, sAbuseReson, sizeof(sAbuseReson));
			
			g_arAbuseSendInfo[iClient].PushString(sAbuseReson);
			
			CreateConfirmMenu(iClient, sAbuseReson);
			
		}
		case MenuAction_Cancel: {
			
			if (iItem == MenuCancel_ExitBack) {
				
				CreateReportAbuseMenu(iClient);
				
			}
			
		}
		case MenuAction_End: {
			delete hMenu;
		}
		default: {  }
		
	}
	
}
void CreateConfirmMenu(int iClient, const char[] sAbuseReson) {
	
	char sBuffer[128], sName[64];
	Menu hMenu = new Menu(MenuHandler_ConfirmMenu);
	
	SetGlobalTransTarget(iClient);
	
	g_arAbuseSendInfo[iClient].GetString(3, sName, sizeof(sName));
	hMenu.SetTitle("%t", "Confirm_Title", sName);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Confirm_Abuse", sAbuseReson);
	hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Confirm_Accept");
	hMenu.AddItem("", sBuffer);
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Confirm_Cancelled");
	hMenu.AddItem("", sBuffer);
	
	hMenu.ExitBackButton = false;
	hMenu.ExitButton = false;
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	
}
_MenuHandler(MenuHandler_ConfirmMenu) {
	
	switch (iAction) {
		
		case MenuAction_Select: {
			
			if (iItem == 1) {
				
				SendTicket(iClient);
				
				// Отправить жалобу
				// Вывести игроку сообщение об успешной отправке
				// С предложением открыть информацию о жалобе
				
				if (g_dpAlertInfo[iClient]) {
					delete g_dpAlertInfo[iClient];
				}
				
				return 0;
				
			}
			
			// Отменить отправку жалобы
			
			//g_arAbuseSendInfo[iClient].Clear();
			delete g_arAbuseSendInfo[iClient];
			
			CreateURSMenu(iClient);
		}
		case MenuAction_End: {
			delete hMenu;
		}
		default: {  }
		
	}
	
	return 0;
}

void CreateMyComplaintsMenu(int iClient) {
	
	LoadTickets(iClient, true);
	
}
_MenuHandler(MenuHandler_MCMenu) {
	
	switch (iAction) {
		
		case MenuAction_Select: {
			
			char sComplaintID[5];
			hMenu.GetItem(iItem, sComplaintID, sizeof(sComplaintID));
			
			CreateTicketInfoMenu(iClient, sComplaintID);
			
		}
		case MenuAction_Cancel: {
			
			if (iItem == MenuCancel_ExitBack) {
				
				CreateURSMenu(iClient);
				
			}
			
		}
		case MenuAction_End: {
			delete hMenu;
		}
		default: {  }
		
	}
	
}

void CreateMyViolationsMenu(int iClient) {
	
	LoadTickets(iClient, false);
	
}
_MenuHandler(MenuHandler_MVMenu) {
	
	switch (iAction) {
		
		case MenuAction_Select: {
			
			char sViolationID[5];
			hMenu.GetItem(iItem, sViolationID, sizeof(sViolationID));
			
			CreateTicketInfoMenu(iClient, sViolationID);
			
		}
		case MenuAction_Cancel: {
			
			if (iItem == MenuCancel_ExitBack) {
				
				CreateURSMenu(iClient);
				
			}
			
		}
		case MenuAction_End: {
			delete hMenu;
		}
		default: {  }
		
	}
	
}
public void CreateTicketInfoMenu(int iClient, const char[] sTicketID) {
	
	DataPack dpTicket;
	if (g_smTickets.Size == 0 || g_smTickets.GetValue(sTicketID, dpTicket) == false || dpTicket == null) {
		
		LoadTicket(iClient, sTicketID);
		
	} else {
		
		char sCID[64], sUID[64], sAID[64], sTicket[64], sPText[64], sBuffer[128], sTime[32];
		int iStatus, iPType, iTime, iPTime, iATime;
		
		dpTicket.Reset();
		dpTicket.ReadString(sCID, sizeof(sCID));
		dpTicket.ReadString(sUID, sizeof(sUID));
		dpTicket.ReadString(sTicket, sizeof(sTicket));
		iStatus = dpTicket.ReadCell();
		iTime = dpTicket.ReadCell();
		if (iStatus != 0) {
			iPType = dpTicket.ReadCell();
			iPTime = dpTicket.ReadCell();
			dpTicket.ReadString(sPText, sizeof(sPText));
			iATime = dpTicket.ReadCell();
			dpTicket.ReadString(sAID, sizeof(sAID));
		}
		
		Panel hPanel = new Panel();
		
		SetGlobalTransTarget(iClient);
		
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "Ticket_Title", sTicketID);
		hPanel.SetTitle(sBuffer);
		
		FormatEx(sBuffer, sizeof(sBuffer), "%T", "Ticket_CID", sCID); hPanel.DrawText(sBuffer);
		
		if (_Players[iClient][bC]) {
			FormatEx(sBuffer, sizeof(sBuffer), "%T", "Ticket_UID", sUID);
			hPanel.DrawText(sBuffer);
		}
		
		FormatTime(sTime, sizeof(sTime), "%d.%m.%Y %H:%M:%S", iTime);
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "Ticket_SendTime", sTime); hPanel.DrawText(sBuffer);
		
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "Ticket_Status", iStatus == 1 ? "Ticket_StatusDiscussed":"Ticket_StatusPending"); hPanel.DrawText(sBuffer);
		
		if (iStatus != 0) {
			FormatEx(sBuffer, sizeof(sBuffer), "%t", "Ticket_AID", sAID); hPanel.DrawText(sBuffer);
		}
		hPanel.CurrentKey = 8;
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "Back"); hPanel.DrawItem(sBuffer);
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "Exit"); hPanel.DrawItem(sBuffer);
		
		hPanel.Send(iClient, MenuHandler_TIMenu, MENU_TIME_FOREVER);
		
		delete hPanel;
		
		// TODO
		FakaFunc(iATime, iPType, iPTime);
		
	}
	
}
_MenuHandler(MenuHandler_TIMenu) {
	
	if (iAction == MenuAction_Select) {
		
		if (iItem == 8) {
			if (_Players[iClient][bC])
				CreateMyComplaintsMenu(iClient);
			else
				CreateMyViolationsMenu(iClient);
			return;
		}
		
	}
	
}

// Thx Kailo
// Преобразует время в секундах в строку, пример: 3756 -> "1ч 02м 36с"
void GetStringTime(int time, char[] buffer, int maxlength)
{
	// TODO
	static int dims[] =  { 60, 60, 24, 30, 365, cellmax };
	static char sign[][] =  { "с", "м", "ч", "д", "м", "г" };
	static char form[][] =  { "%02i%s%s", "%02i%s %s", "%i%s %s" };
	buffer[0] = EOS;
	int i = 0, f = -1;
	bool cond = false;
	while (!cond) {
		if (f++ == 1)
			cond = true;
		do {
			Format(buffer, maxlength, form[f], time % dims[i], sign[i], buffer);
			if (time /= dims[i++], time == 0)
				return;
		} while (cond);
	}
}

void CreateRewardsMenu(int iClient) {
	
	Menu hMenu = new Menu(MenuHandler_RMenu);
	
	int iVar = 10;
	if (_Players[iClient][bLoad] == true) { iVar = _Players[iClient][iBalls]; }
	
	SetGlobalTransTarget(iClient);
	
	hMenu.SetTitle("%t", "Rewards_MainTitle", iVar);
	
	char sBuffer[64], sReward[32];
	for (int i = 0; i < g_arRewards.Length; i++) {
		g_arRewards.GetString(i, sReward, sizeof(sReward));
		FormatEx(sBuffer, sizeof(sBuffer), "%t", sReward);
		sBuffer[63] = '\0';
		hMenu.AddItem("", sBuffer);
	}
	
	if (hMenu.ItemCount == 0) {
		FormatEx(sBuffer, sizeof(sBuffer), "%t", "Rewards_Empty");
		hMenu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	}
	
	hMenu.ExitBackButton = true;
	hMenu.ExitButton = true;
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	
}
_MenuHandler(MenuHandler_RMenu) {
	
	switch (iAction) {
		
		case MenuAction_Select: {
			
			char sReward[64];
			g_arRewards.GetString(iItem, sReward, sizeof(sReward));
			
			Forward_OnClientChoseReward(iClient, sReward);
		}
		case MenuAction_Cancel: {
			
			if (iItem == MenuCancel_ExitBack) {
				
				CreateURSMenu(iClient);
				
			}
			
		}
		case MenuAction_End: {
			delete hMenu;
		}
		default: {  }
		
	}
	
}

public void CreateAlertPanel(int iClient, char[] sTitle, char[] sText, const char[] sItem) {
	
	char sBuffer[256];
	Panel hPanel = new Panel();
	
	SetGlobalTransTarget(iClient);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", sTitle);
	hPanel.SetTitle(sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "%t", sText);
	hPanel.DrawText(sBuffer);
	
	if (sItem[0] != '\0') {
		FormatEx(sBuffer, sizeof(sBuffer), "%t", sItem);
		hPanel.DrawItem(sBuffer);
	}
	
	hPanel.CurrentKey = 9;
	FormatEx(sBuffer, sizeof(sBuffer), "%t", "Exit"); hPanel.DrawItem(sBuffer);
	
	hPanel.Send(iClient, MenuHandler_AlertPanel, MENU_TIME_FOREVER);
	
	delete hPanel;
	
}
_MenuHandler(MenuHandler_AlertPanel) {
	
	if (iAction == MenuAction_Select) {
		
		if (iItem == 1 && g_dpAlertInfo[iClient] != null) {
			char sBuffer[16];
			
			g_dpAlertInfo[iClient].Reset();
			Function fFunc = g_dpAlertInfo[iClient].ReadFunction();
			g_dpAlertInfo[iClient].ReadString(sBuffer, sizeof(sBuffer));
			
			Call_StartFunction(INVALID_HANDLE, fFunc);
			Call_PushCell(iClient);
			if (sBuffer[0] != '\0') {
				Call_PushString(sBuffer);
			}
			Call_Finish();
			
			delete g_dpAlertInfo[iClient];
			
			return;
		}
		
	}
	 
	if (iAction == MenuAction_Cancel) {
		PrintToChatAll("PANEL: MenuAction_Cancel ");
	}
	if (iAction == MenuAction_End) {
		PrintToChatAll("PANEL: MenuAction_End ");
	}
	
}

void ClearPlayer(int iClient) {
	
	for (int i = 0; i < 5; i++) {
		_Players[iClient][i] = false;
	}
	
	for (int i = 5; i < sizeof(_Players[]); i++) {
		_Players[iClient][i] = -1;
	}
	
}

public void OnClientPostAdminCheck(int iClient) {
	
	if (IsFakeClient(iClient) || IsClientSourceTV(iClient) || IsClientReplay(iClient)) {
		return;
	}
	
	CreateTimer(20.0, Timer_OnClientConnected, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	
	ClearPlayer(iClient);
	
}
public Action Timer_OnClientConnected(Handle timer, any iUserID) {
	
	int iClient;
	if (!(iClient = GetClientOfUserId(iUserID))) {
		return Plugin_Stop;
	}
	
	char sSteamID[32];
	GetClientAuthId(iClient, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	
	if (!strcmp(sSteamID, "STEAM_ID_PENDING")) {
		CreateTimer(3.0, Timer_OnClientConnected, iUserID, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}
	
	char sQuery[128];
	FormatEx(sQuery, sizeof(sQuery), "SELECT `id`,`balls`,`rating`,`grp` FROM `Users` WHERE `auth` = '%s' LIMIT 1;", sSteamID);
	
	g_hDatabase.Query(SQL_Callback_OnClientConnected, sQuery, iUserID);
	
	return Plugin_Stop;
	
}

SQLCB(SQL_Callback_OnClientConnected) {
	if (szError[0] || !results) {
		LogError("SQL_Callback_OnClientConnected: '%s'", szError);
		return;
	}
	
	int iClient;
	if (!(iClient = GetClientOfUserId(data))) {
		return;
	}
	
	if (!results.FetchRow()) {
		// Клиента нет в базе, надо его записать?
		
		InsertPlayer(iClient);
		
		return;
	}
	
	// Клиент есть в базе, делаем запрос на блокировки
	_Players[iClient][bLoad] = true;
	
	_Players[iClient][iID] = results.FetchInt(0);
	_Players[iClient][iBalls] = results.FetchInt(1);
	_Players[iClient][iRating] = results.FetchInt(2);
	_Players[iClient][iGrp] = results.FetchInt(3);
	
	char sSteamID[32], sQuery[128];
	GetClientAuthId(iClient, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	
	FormatEx(sQuery, sizeof(sQuery), "SELECT `uid` FROM `Tickets` WHERE `uid` = '%i' LIMIT 1;", _Players[iClient][iID]);
	g_hDatabase.Query(SQL_Callback_OnCheckComplains, sQuery, data);
	
	FormatEx(sQuery, sizeof(sQuery), "SELECT `cid` FROM `Tickets` WHERE `cid` = '%i' AND  (`status` = '1' OR `status` = '3') LIMIT 1;", _Players[iClient][iID]);
	g_hDatabase.Query(SQL_Callback_OnCheckViolations, sQuery, data);
}

SQLCB(SQL_Callback_OnCheckComplains) {
	if (szError[0] || !results) {
		LogError("SQL_Callback_OnCheckComplains: '%s'", szError);
		return;
	}
	
	int iClient;
	if (!(iClient = GetClientOfUserId(data))) {
		return;
	}
	
	_Players[iClient][bComplain] = (results.FetchRow() && _Players[iClient][iID] == results.FetchInt(0));
}
SQLCB(SQL_Callback_OnCheckViolations) {
	if (szError[0] || !results) {
		LogError("SQL_Callback_OnCheckViolations: '%s'", szError);
		return;
	}
	
	int iClient;
	if (!(iClient = GetClientOfUserId(data))) {
		return;
	}
	
	_Players[iClient][bViolation] = (results.FetchRow() && _Players[iClient][iID] == results.FetchInt(0));
	
	ReOpenURS(iClient);
}
void ReOpenURS(int iClient) {
	
	if (_Players[iClient][bMenu]) {
		_Players[iClient][bMenu] = false;
		CreateURSMenu(iClient);
	}
	
}
void InsertPlayer(int iClient) {
	
	char sTargetSteamID[32], sName[MAX_NAME_LENGTH], sQuery[256];
	GetClientAuthId(iClient, AuthId_SteamID64, sTargetSteamID, sizeof(sTargetSteamID));
	GetClientName(iClient, sName, sizeof(sName));
	
	char[] szEscapedName = new char[2 * strlen(sName) + 1];
	g_hDatabase.Escape(sName, szEscapedName, 2 * strlen(sName) + 1);
	
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `Users` (`id`, `auth`, `name`, `balls`, `rating`, `grp`) VALUES (NULL, '%s', '%s', '%i', '%i', '%i');", sTargetSteamID, szEscapedName, _iBalls, _iRating, 0);
	g_hDatabase.Query(SQL_Callback_OnInsertPlayer, sQuery, GetClientUserId(iClient));
}

SQLCB(SQL_Callback_OnInsertPlayer) {
	if (szError[0] || !results) {
		LogError("SQL_Callback_OnInsertPlayer: '%s'", szError);
		return;
	}
	
	int iClient;
	if (!(iClient = GetClientOfUserId(data))) {
		return;
	}
	
	_Players[iClient][bLoad] = true;
	
	_Players[iClient][iID] = results.InsertId;
	_Players[iClient][iBalls] = _iBalls;
	_Players[iClient][iRating] = _iRating;
	_Players[iClient][iGrp] = 0;
	
	_Players[iClient][bComplain] = false;
	
	_Players[iClient][bViolation] = false;
}


void SendTicket(int iClient, bool bLog = false, bool bSql = true) {
	
	char sName[32], sAbuseReson[64];
	int iUserID, iGameTickCount, iTimeStamp;
	
	iTimeStamp = g_arAbuseSendInfo[iClient].Get(0);
	iGameTickCount = g_arAbuseSendInfo[iClient].Get(1);
	iUserID = g_arAbuseSendInfo[iClient].Get(2);
	g_arAbuseSendInfo[iClient].GetString(3, sName, sizeof(sName));
	g_arAbuseSendInfo[iClient].GetString(4, sAbuseReson, sizeof(sAbuseReson));
	
	char[] szEscapedName = new char[2 * strlen(sName) + 1];
	g_hDatabase.Escape(sName, szEscapedName, 2 * strlen(sName) + 1);
	
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `Tickets` (`id`, `cid`, `uid`, `sid`, `ticket`, `status`, `ptype`, `ptime`, `ptext`, `atime`, `map`, `itime`, `itick`) VALUES (NULL, '%i', '%i', '%i', '%s', '%i', '%i', '%i', '%s', '%i', '%s', '%i', '%i');", iUserID, _Players[iClient][iID], 0, sAbuseReson, 0, 0, 0, "", 0, g_sMap, iTimeStamp, iGameTickCount);
	
	if (bSql) {
		g_hDatabase.Query(SQL_Callback_OnSendTicket, sQuery, GetClientUserId(iClient));
	}
	
	if (bLog) {
		LogToFileEx("addons/sourcemod/logs/urs_tickets.log", "ERROR! Ticket: '%s'", sQuery);
	}
	
}
SQLCB(SQL_Callback_OnSendTicket) {
	
	int iClient;
	if (!(iClient = GetClientOfUserId(data))) {
		return;
	}
	
	if (szError[0] || !results) {
		LogError("SQL_Callback_OnSendTicket: '%s'", szError);
		
		SendTicket(iClient, true, false);
		/*
		g_dpAlertInfo[iClient] = new DataPack();
		g_dpAlertInfo[iClient].WriteFunction(CreateURSMenu);
		g_dpAlertInfo[iClient].WriteString("");
		*/
		
		CreateAlertPanel(iClient, "AlertTitle_SystemError", "AlertText_CmplaintNotSent", "");
		
		return;
	}
	
	g_arAbuseSendInfo[iClient].Clear();
	delete g_arAbuseSendInfo[iClient];
	
	char sTicketID[6];
	IntToString(results.InsertId, sTicketID, sizeof(sTicketID));
	
	g_dpAlertInfo[iClient] = new DataPack();
	g_dpAlertInfo[iClient].WriteFunction(CreateTicketInfoMenu);
	g_dpAlertInfo[iClient].WriteString(sTicketID);
	
	CreateAlertPanel(iClient, "AlertTitle_Notification", "AlertText_ComplaintSent", "AlertItem_ComplaintAbout");
	
	LogToFileEx("addons/sourcemod/logs/urs_tickets.log", "Ticket #%s sent", sTicketID);
}

void LoadTicket(int iClient, const char[] sTicketID) {
	
	DataPack dpTicket = new DataPack();
	
	dpTicket.WriteCell(GetClientUserId(iClient));
	dpTicket.WriteString(sTicketID);
	
	char sQuery[356];
	FormatEx(sQuery, sizeof(sQuery), "SELECT `id`, (SELECT `name` FROM `Users` WHERE `id` = `cid` LIMIT 1) AS `cid`,(SELECT `name` FROM `Users` WHERE `id` = `uid` LIMIT 1) AS `uid`,`ticket`,`status`,`itime`,`ptype`,`ptime`,`ptext`,`atime`,(SELECT `name` FROM `Users` WHERE `id` = `aid` LIMIT 1) AS `aid`FROM `Tickets` WHERE `id` = '%s' LIMIT 1;", sTicketID);
	g_hDatabase.Query(SQL_Callback_OnLoadTicket, sQuery, dpTicket);
	
}
SQLCB(SQL_Callback_OnLoadTicket) {
	
	DataPack dpLocal = view_as<DataPack>(data);
	dpLocal.Reset();
	
	int iClient;
	if (!(iClient = GetClientOfUserId(dpLocal.ReadCell()))) {
		delete dpLocal;
		return;
	}
	
	if (szError[0] || !results) {
		LogError("SQL_Callback_OnLoadTicket: '%s'", szError);
		
		g_dpAlertInfo[iClient] = new DataPack();
		g_dpAlertInfo[iClient].WriteFunction(CreateURSMenu);
		g_dpAlertInfo[iClient].WriteString("");
		
		CreateAlertPanel(iClient, "AlertTitle_SystemError", "AlertText_TicketErrorLoading", "AlertItem_GotoMainMenu");
		
		delete dpLocal;
		
		return;
	}
	
	char sTicketID[6];
	dpLocal.ReadString(sTicketID, sizeof(sTicketID));
	
	dpLocal.Reset();
	delete dpLocal;
	
	if (g_smTickets.GetValue(sTicketID, dpLocal) == true && dpLocal == null) {
		CreateTicketInfoMenu(iClient, sTicketID);
		return;
	}
	
	if (results.FetchRow() == false) {
		g_dpAlertInfo[iClient] = new DataPack();
		g_dpAlertInfo[iClient].WriteFunction(CreateURSMenu);
		g_dpAlertInfo[iClient].WriteString("");
		
		CreateAlertPanel(iClient, "AlertTitle_SystemError", "AlertText_TicketErrorLoading", "AlertItem_GotoMainMenu");
		return;
	}
	
	char sCID[64], sUID[64], sAID[64], sTicket[64], sPText[64];
	int iStatus, iPType, iTime, iPTime, iATime;
	
	results.FetchString(1, sCID, sizeof(sCID));
	results.FetchString(2, sUID, sizeof(sUID));
	results.FetchString(3, sTicket, sizeof(sTicket));
	iStatus = results.FetchInt(4);
	iTime = results.FetchInt(5);
	if (iStatus != 0) {
		iPType = results.FetchInt(6);
		iPTime = results.FetchInt(7);
		results.FetchString(8, sPText, sizeof(sPText));
		iATime = results.FetchInt(9);
		results.FetchString(10, sAID, sizeof(sAID));
	}
	
	dpLocal = new DataPack();
	dpLocal.WriteString(sCID);
	dpLocal.WriteString(sUID);
	dpLocal.WriteString(sTicket);
	dpLocal.WriteCell(iStatus);
	dpLocal.WriteCell(iTime);
	if (iStatus != 0) {
		dpLocal.WriteCell(iPType);
		dpLocal.WriteCell(iPTime);
		dpLocal.WriteString(sPText);
		dpLocal.WriteCell(iATime);
		dpLocal.WriteString(sAID);
	}
	
	if (g_smTickets.Size == 10) {
		StringMapSnapshot smSMS = g_smTickets.Snapshot();
		smSMS.GetKey(smSMS.Length - 1, sCID, sizeof(sCID));
		if (g_smTickets.Remove(sCID) == false) {
			g_smTickets.Clear();
		}
	}
	
	g_smTickets.SetValue(sTicketID, dpLocal);
	CreateTicketInfoMenu(iClient, sTicketID);
	
}

void LoadTickets(int iClient, bool bComplaint = true) {
	
	_Players[iClient][bC] = bComplaint;
	
	char sQuery[356];
	FormatEx(sQuery, sizeof(sQuery), \
		"SELECT `id`,(SELECT `name` FROM `Users` WHERE `id` = `%sid` LIMIT 1) AS `name` FROM `Tickets` WHERE `%sid` = '%i';", \
		bComplaint ? "c":"u", bComplaint ? "u":"c", _Players[iClient][iID]);
	g_hDatabase.Query(SQL_Callback_OnLoadTickets, sQuery, GetClientUserId(iClient));
	
}
SQLCB(SQL_Callback_OnLoadTickets) {
	
	int iClient;
	if (!(iClient = GetClientOfUserId(data))) {
		return;
	}
	
	if (szError[0] || !results) {
		LogError("SQL_Callback_OnLoadTickets: '%s'", szError);
		
		g_dpAlertInfo[iClient] = new DataPack();
		g_dpAlertInfo[iClient].WriteFunction(CreateURSMenu);
		g_dpAlertInfo[iClient].WriteString("");
		
		CreateAlertPanel(iClient, "AlertTitle_SystemError", "AlertText_TicketErrorLoading", "AlertItem_GotoMainMenu");
		
		return;
	}
	// TODO
	Menu hMenu = new Menu(_Players[iClient][bC] ? MenuHandler_MCMenu : MenuHandler_MVMenu);
	hMenu.SetTitle(_Players[iClient][bC] ? "Ваши жалобы: " : "Жалобы на вас: ");
	
	if (results.FetchRow()) {
		
		char sTicketID[6], sName[32], sBuffer[64];
		int id;
		DataPack dpLocal;
		
		do {
			
			id = results.FetchInt(0);
			IntToString(id, sTicketID, sizeof(sTicketID));
			
			if (g_smTickets.GetValue(sTicketID, dpLocal) == true && dpLocal == null) {
				continue;
			}
			
			results.FetchString(1, sName, sizeof(sName));
			sName[31] = '\0';
			
			FormatEx(sBuffer, sizeof(sBuffer), "%s [#%s]", sName, sTicketID);
			hMenu.AddItem(sTicketID, sBuffer);
			
		} while (results.FetchRow());
		
	} else {
		hMenu.AddItem("", _Players[iClient][bC] ? "Вы не оставляли жалобы" : "На вас не поступало жалоб", ITEMDRAW_DISABLED);
	}
	
	hMenu.ExitBackButton = true;
	hMenu.ExitButton = true;
	
	hMenu.Display(iClient, MENU_TIME_FOREVER);
	
}

stock void FakaFunc(any...) {  }

void CreateForwards() {
	
	g_fwdOnClientChoseReward = CreateGlobalForward(
		"URS_OnClientChoseReward", 
		ET_Event, 
		Param_Cell, Param_String, Param_CellByRef);
	
}

bool Forward_OnClientChoseReward(const int iClient, const char[] sReward) {
	
	int iResult, iCost;
	
	Call_StartForward(g_fwdOnClientChoseReward);
	Call_PushCell(iClient);
	Call_PushString(sReward);
	Call_PushCellRef(iCost);
	Call_Finish(iResult);
	
	if (iResult == 1) {
		
		if (iCost < 0) { iCost *= -1; }
		
		_Players[iClient][iBalls] -= iCost;
		
		if (g_dpAlertInfo[iClient]) {
			delete g_dpAlertInfo[iClient];
		}
		
		g_dpAlertInfo[iClient] = new DataPack();
		g_dpAlertInfo[iClient].WriteFunction(CreateURSMenu);
		g_dpAlertInfo[iClient].WriteString("");
		
		CreateAlertPanel(iClient, "AlertTitle_Notification", "AlertText_Congratulate", "AlertItem_GotoMainMenu");
		
	}
	
	return iResult == 1;
	
} 