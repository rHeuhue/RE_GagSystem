#include <amxmodx>
#include <amxmisc>
#include <reapi_stocks>
#include <regex>
#include <nvault>

#define CC_COLORS_TYPE CC_COLORS_SHORT
#include <cromchat>

#pragma semicolon 1

#define LOG_GAGS

#define IP_PATTERN "([0-9]+.*[1-9][0-9]+.*[0-9]+.*[0-9])"
#define PLUGIN "RE: Gag System"
#define VERSION "1.5"

#define MAX_REASON_LENGHT 64

enum _:GagState
{
	GAG_NOT,
	GAG_YES,
	GAG_EXPIRED
};

new const g_szVaultName[] = "re_gag_system";
new const g_szChatPrefix[] = "!g[RE: GagSystem]!n";
new const g_szGagSound[] = "buttons/blip1.wav";
#if defined LOG_GAGS
new const g_szLogFile[] = "addons/amxmodx/logs/gag_system.log";
#endif

new g_iNVaultHandle, Regex:g_iRegexIPPattern, g_iUnused, g_iThinkingEnt;
new g_iUserTarget[MAX_PLAYERS + 1], bool:g_blIsUserMuted[MAX_PLAYERS + 1];
new g_GagForward, g_UngagForward;

new g_iMenuPosition[MAX_PLAYERS + 1],
	g_iMenuPlayers[MAX_PLAYERS + 1][MAX_PLAYERS],
	g_iMenuPlayersNum[MAX_PLAYERS + 1],
	g_iMenuOption[MAX_PLAYERS + 1],
	g_iMenuSettings[MAX_PLAYERS + 1],
	g_iMenuReasonOption[MAX_PLAYERS + 1],
	g_iMenuSettingsReason[MAX_PLAYERS + 1][MAX_REASON_LENGHT];

new Array:g_aGagTimes,
	Array:g_aGagReason,
	g_iGagTime;

// Updates
enum eLists
{
	BLACK,
	WHITE,
	BAD_NAME_REPLACEMENTS
}
new Array:g_aList[eLists], g_iTotalPhrases[eLists];
new g_szName[MAX_PLAYERS + 1][MAX_NAME_LENGTH], g_szIP[MAX_PLAYERS + 1][MAX_IP_LENGTH];

// New cvar settings
new gp_blHudEnabled, gp_blEnableGagExpireMsg,
	gp_iAutoGagTime_BadWords, gp_iAutoGagTime_Advertise, gp_iAutoGagTime_BadName, gp_iAutoGagTime_SpamChat, 
	gp_szAdminBadWords[MAX_NAME_LENGTH], gp_szAdminAdvertise[MAX_NAME_LENGTH],
	gp_szReasonBadWords[MAX_NAME_LENGTH], gp_szReasonAdvertise[MAX_NAME_LENGTH],
	gp_szReasonBadName[MAX_NAME_LENGTH], gp_szAdminBadName[MAX_NAME_LENGTH],
	gp_szReasonSpamChat[MAX_NAME_LENGTH], gp_szAdminSpamChat[MAX_NAME_LENGTH];

new gp_iSpamCount, gp_IgnoreAdmins_Immunity;

new g_szPlayerLastMessage[MAX_PLAYERS + 1][192];

new g_iSpamCount[MAX_PLAYERS + 1], g_szLastSaidSpam[MAX_PLAYERS + 1][192];

new bool:g_bForced_Name_Change, bool:g_bBadNameDetected;


public plugin_init()
{
	register_plugin(PLUGIN, VERSION, "TheRedShoko, Huehue");
	register_cvar("re_gagsystem_amxxbg", VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED);

	register_clcmd("say", "CommandSayExecuted");
	register_clcmd("say_team", "CommandSayExecuted");

	g_GagForward = CreateMultiForward("user_gagged", ET_IGNORE, FP_CELL);
	g_UngagForward = CreateMultiForward("user_ungagged", ET_IGNORE, FP_CELL);

	bind_pcvar_num(create_cvar("regs_show_hud", "1", FCVAR_NONE, "Enables/Disables the hud messages", true, 0.0, true, 1.0), gp_blHudEnabled);
	bind_pcvar_num(create_cvar("regs_print_expired", "1", FCVAR_NONE, "Enables/Disables the messages when gag expire", true, 0.0, true, 1.0), gp_blEnableGagExpireMsg);
	bind_pcvar_num(create_cvar("regs_immunity_autogags", "1", FCVAR_NONE, "Enables/Disables the admin immunity for auto gags part", true, 0.0, true, 1.0), gp_IgnoreAdmins_Immunity);
	
	bind_pcvar_num(create_cvar("regs_autogag_time_bad_words", "5", FCVAR_NONE, "How many minutes gag will be applied when player uses words from blacklist"), gp_iAutoGagTime_BadWords);
	bind_pcvar_num(create_cvar("regs_autogag_time_advertise", "5", FCVAR_NONE, "How many minutes gag will be applied when player uses ip/sites pattern"), gp_iAutoGagTime_Advertise);
	bind_pcvar_num(create_cvar("regs_autogag_time_bad_name", "5", FCVAR_NONE, "How many minutes gag will be applied when player uses ip/sites/bad words pattern in name"), gp_iAutoGagTime_BadName);
	bind_pcvar_num(create_cvar("regs_autogag_time_spam_chat", "5", FCVAR_NONE, "How many minutes gag will be applied when player uses same messages in a row in the chat"), gp_iAutoGagTime_SpamChat);
	bind_pcvar_num(create_cvar("regs_autogag_spam_count", "3", FCVAR_NONE, "How many messages will count as spam when repeated again and again"), gp_iSpamCount);

	bind_pcvar_string(create_cvar("regs_autogag_admin_name_bad_words", "AutoGag_BLW", FCVAR_NONE, "What name will be shown as administrator when player is gagged using blacklist words"), gp_szAdminBadWords, charsmax(gp_szAdminBadWords));
	bind_pcvar_string(create_cvar("regs_autogag_admin_name_regex", "AutoGag_RGXP", FCVAR_NONE, "What name will be shown as administrator when player is gagged using ip/sites pattern"), gp_szAdminAdvertise, charsmax(gp_szAdminAdvertise));
	bind_pcvar_string(create_cvar("regs_autogag_admin_name_bad_name", "AutoGag_BN", FCVAR_NONE, "What name will be shown as administrator when player is gagged using ip/sites/bad words pattern"), gp_szAdminBadName, charsmax(gp_szAdminBadName));
	bind_pcvar_string(create_cvar("regs_autogag_admin_name_spam_chat", "AutoGag_SC", FCVAR_NONE, "What name will be shown as administrator when player is gagged spamming in chat"), gp_szAdminSpamChat, charsmax(gp_szAdminSpamChat));

	bind_pcvar_string(create_cvar("regs_autogag_reason_bad_words", "BlackList Words Detected", FCVAR_NONE, "What reason will be shown as gag when player is gagged using blacklist words"), gp_szReasonBadWords, charsmax(gp_szReasonBadWords));
	bind_pcvar_string(create_cvar("regs_autogag_reason_regex", "Regex Pattern Detected", FCVAR_NONE, "What reason will be shown as gag when player is gagged using ip/sites pattern"), gp_szReasonAdvertise, charsmax(gp_szReasonAdvertise));
	bind_pcvar_string(create_cvar("regs_autogag_reason_bad_name", "Bad Name Detected", FCVAR_NONE, "What reason will be shown as gag when player is gagged using ip/sites/bad words pattern"), gp_szReasonBadName, charsmax(gp_szReasonBadName));
	bind_pcvar_string(create_cvar("regs_autogag_reason_spam_chat", "Spam Chat Detected", FCVAR_NONE, "What reason will be shown as gag when player is gagged spamming in chat"), gp_szReasonSpamChat, charsmax(gp_szReasonSpamChat));

	RegisterHookChain(RG_CSGameRules_CanPlayerHearPlayer, "RG__CSGameRules_CanPlayerHearPlayer");
	RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "RG__CBasePlayer_SetClientUserInfoName");

	register_clcmd("amx_gag", "CommandGag", ADMIN_SLAY, "<name | #id | ip> <time> <reason> <admin reason>");
	register_clcmd("amx_ungag", "CommandUngag", ADMIN_SLAY, "<name | #id | ip>");
	register_clcmd("amx_gagmenu", "cmdGagMenu", ADMIN_SLAY, "- displays gag/ungag menu");
	register_clcmd("amx_TYPE_GAGREASON", "CommandGagReason", ADMIN_SLAY);
	register_clcmd("amx_cleangags", "CommandCleanDB", ADMIN_RCON);

	register_menucmd(register_menuid("Gag Menu"), 1023, "actionGagMenu");

	register_message(get_user_msgid("SayText"), "Block_NameChange_OnGagDetect");

	g_iRegexIPPattern = regex_compile_ex(IP_PATTERN);

	g_iNVaultHandle = nvault_open(g_szVaultName);

	if (g_iNVaultHandle == INVALID_HANDLE)
	{
		set_fail_state("Failed to open NVault DB!");
	}
	
	g_aGagTimes = ArrayCreate();
	ArrayPushCell(g_aGagTimes, 0);
	ArrayPushCell(g_aGagTimes, 5);
	ArrayPushCell(g_aGagTimes, 10);
	ArrayPushCell(g_aGagTimes, 30);
	ArrayPushCell(g_aGagTimes, 60);
	ArrayPushCell(g_aGagTimes, 1440);
	ArrayPushCell(g_aGagTimes, 10080);
	
	register_srvcmd("amx_menu_gag_times", "amx_menu_setgagtimes");
	
	g_aGagReason = ArrayCreate(64, 1);
	ArrayPushString(g_aGagReason, "Custom Reason");
	ArrayPushString(g_aGagReason, "Flame");
	ArrayPushString(g_aGagReason, "Swearing");
	ArrayPushString(g_aGagReason, "Lame");
	ArrayPushString(g_aGagReason, "Offensive Language");
	ArrayPushString(g_aGagReason, "Spam In Chat");
	
	register_srvcmd("amx_menu_gag_reasons", "amx_menu_setgagreasons");

	g_iThinkingEnt = rg_create_entity("info_target");
	set_entvar(g_iThinkingEnt, var_nextthink, get_gametime() + 0.1);
	SetThink(g_iThinkingEnt, "RG__Entity_Think");

	AutoExecConfig(true, "RGS_Settings", "RE_Gag_System");

	CC_SetPrefix(g_szChatPrefix);
}

public plugin_precache()
{
	precache_sound(g_szGagSound);

	g_aList[WHITE] = ArrayCreate(128, 1);
	g_aList[BLACK] = ArrayCreate(128, 1);
	g_aList[BAD_NAME_REPLACEMENTS] = ArrayCreate(32, 1);

	Load_BlackList();
	Load_WhiteList();
	Load_BadName_ReplacementsList();
}

public Load_BlackList()
{
	static szConfigsDir[64], iFile, szBlackList[64];
	get_configsdir(szConfigsDir, charsmax(szConfigsDir));
	formatex(szBlackList, charsmax(szBlackList), "/plugins/RE_Gag_System/RGS_BlackList.ini");
	add(szConfigsDir, charsmax(szConfigsDir), szBlackList);
	iFile = fopen(szConfigsDir, "rt");

	if(!file_exists(szConfigsDir))
	{
		server_print("File not found, creating new one..");
		new iFile = fopen(szConfigsDir, "wt");
		
		if (iFile)
		{
			new szNewFile[512];
			formatex(szNewFile, charsmax(szNewFile), "// Add here your blacklist phrases or words\
				^n// Example: [Add quotes ^"for phrases^" or only word for single word\
				^ngei\
				^npedal\
				^n^"fuck you^"\
				^nfuck");
			fputs(iFile, szNewFile);
		}
		fclose(iFile);
		Load_BlackList();
		return;
	}

	new iLine;
	
	if (iFile)
	{
		static szLineData[256], szWords[128];
		
		while (!feof(iFile))
		{
			fgets(iFile, szLineData, charsmax(szLineData));
			trim(szLineData);
			
			if (szLineData[0] == EOS || szLineData[0] == ';' || (szLineData[0] == '/' && szLineData[1] == '/'))
				continue;

			parse(szLineData, szWords, charsmax(szWords));

			if (szWords[0] == EOS)
				continue;

			ArrayPushString(Array:g_aList[BLACK], szWords);

			iLine++;
		}
		fclose(iFile);
	}
	g_iTotalPhrases[BLACK] = iLine;
	server_print("[%s] Loaded %i black list phrases or words from file!", PLUGIN, g_iTotalPhrases[BLACK]);
}

public Load_WhiteList()
{
	static szConfigsDir[64], iFile, szWhiteList[64];
	get_configsdir(szConfigsDir, charsmax(szConfigsDir));
	formatex(szWhiteList, charsmax(szWhiteList), "/plugins/RE_Gag_System/RGS_WhiteList.ini");
	add(szConfigsDir, charsmax(szConfigsDir), szWhiteList);
	iFile = fopen(szConfigsDir, "rt");

	if(!file_exists(szConfigsDir))
	{
		server_print("File not found, creating new one..");
		new iFile = fopen(szConfigsDir, "wt");
		
		if (iFile)
		{
			new szNewFile[512];
			formatex(szNewFile, charsmax(szNewFile), "// Add here your white phrases or words\
				^n// Example:\
				^n/top15\
				^n/guns\
				^n/rank");
			fputs(iFile, szNewFile);
		}
		fclose(iFile);
		Load_WhiteList();
		return;
	}

	new iLine;
	
	if (iFile)
	{
		static szLineData[256], szWords[128];
		
		while (!feof(iFile))
		{
			fgets(iFile, szLineData, charsmax(szLineData));
			trim(szLineData);
			
			if (szLineData[0] == EOS || szLineData[0] == ';' || (szLineData[0] == '/' && szLineData[1] == '/'))
				continue;

			parse(szLineData, szWords, charsmax(szWords));

			if (szWords[0] == EOS)
				continue;

			ArrayPushString(Array:g_aList[WHITE], szWords);

			iLine++;
		}
		fclose(iFile);
	}
	g_iTotalPhrases[WHITE] = iLine;
	server_print("[%s] Loaded %i white list phrases or words from file!", PLUGIN, g_iTotalPhrases[WHITE]);
}

public Load_BadName_ReplacementsList()
{
	static szConfigsDir[128], iFile, szBadName_Replacements_List[128];
	get_configsdir(szConfigsDir, charsmax(szConfigsDir));
	formatex(szBadName_Replacements_List, charsmax(szBadName_Replacements_List), "/plugins/RE_Gag_System/RGS_Bad_Name_Replacements.ini");
	add(szConfigsDir, charsmax(szConfigsDir), szBadName_Replacements_List);
	iFile = fopen(szConfigsDir, "rt");

	if(!file_exists(szConfigsDir))
	{
		server_print("File not found, creating new one..");
		new iFile = fopen(szConfigsDir, "wt");
		
		if (iFile)
		{
			new szNewFile[512];
			formatex(szNewFile, charsmax(szNewFile), "// Add here your list of names which players will receive for bad name change\
				^n// Example:\
				^n^"Player^"\
				^n^"AMXX-BG Player^"\
				^n^"RGS BadName^"");
			fputs(iFile, szNewFile);
		}
		fclose(iFile);
		Load_BadName_ReplacementsList();
		return;
	}

	new iLine;
	
	if (iFile)
	{
		static szLineData[256], szName[MAX_NAME_LENGTH];
		
		while (!feof(iFile))
		{
			fgets(iFile, szLineData, charsmax(szLineData));
			trim(szLineData);
			
			if (szLineData[0] == EOS || szLineData[0] == ';' || (szLineData[0] == '/' && szLineData[1] == '/'))
				continue;

			parse(szLineData, szName, charsmax(szName));

			if (szName[0] == EOS)
				continue;

			ArrayPushString(Array:g_aList[BAD_NAME_REPLACEMENTS], szName);

			iLine++;
		}
		fclose(iFile);
	}
	g_iTotalPhrases[BAD_NAME_REPLACEMENTS] = iLine;
	server_print("[%s] Loaded %i names for replacements from file!", PLUGIN, g_iTotalPhrases[BAD_NAME_REPLACEMENTS]);
}

public plugin_end()
{
	nvault_close(g_iNVaultHandle);
	regex_free(g_iRegexIPPattern);
}

public plugin_natives()
{
	register_native("is_user_gagged", "native_is_gagged");

	register_native("gag_user", "native_gag_user");
	register_native("gag_user_byid", "native_gag_id");

	register_native("ungag_user", "native_ungag_user");
	register_native("ungag_user_byid", "native_ungag_id");
}

public native_is_gagged()
{
	new id = get_param(1);
	new bool:shouldPrint = bool:get_param(2);

	if (!is_user_connected(id))
	{
		log_error(AMX_ERR_NATIVE, "Invalid player ID %d", id);
		return false;
	}

	return IsUserGagged(id, shouldPrint) == GAG_YES;
}

public native_gag_user()
{
	new szIP[MAX_IP_LENGTH], szName[MAX_NAME_LENGTH], iDuration, szReason[MAX_REASON_LENGHT], szReasonAdminOnly[MAX_REASON_LENGHT], szAdmin[MAX_NAME_LENGTH];

	get_string(1, szName, charsmax(szName));
	get_string(2, szIP, charsmax(szIP));
	iDuration = get_param(3);
	get_string(4, szReason, charsmax(szReason));
	get_string(5, szReasonAdminOnly, charsmax(szReasonAdminOnly));
	get_string(6, szAdmin, charsmax(szAdmin));

	if (!regex_match_c(szIP, g_iRegexIPPattern, g_iUnused))
	{
		log_error(AMX_ERR_NATIVE, "%s is not a valid IP Address!", szIP);
		return;
	}

	if (iDuration < 0) 
	{
		log_error(AMX_ERR_NATIVE, "Time cannot be negative!");
		return;
	}

	GagUser(szName, szIP, iDuration, szReason, szReasonAdminOnly, szAdmin);
}

public native_gag_id()
{
	new id;

	id = get_param(1);

	if (!is_user_connected(id))
	{
		log_error(AMX_ERR_NATIVE, "Invalid player ID %d", id);
		return;
	}

	new szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH], szReason[MAX_REASON_LENGHT], szReasonAdminOnly[MAX_REASON_LENGHT], iDuration, szAdmin[MAX_NAME_LENGTH];
	iDuration = get_param(2);

	if (iDuration < 0) 
	{
		log_error(AMX_ERR_NATIVE, "Time cannot be negative!");
		return;
	}

	get_string(3, szReason, charsmax(szReason));
	get_string(4, szReasonAdminOnly, charsmax(szReasonAdminOnly));
	get_string(5, szAdmin, charsmax(szAdmin));

	get_user_name(id, szName, charsmax(szName));
	get_user_ip(id, szIP, charsmax(szIP), 1);

	GagUser(szName, szIP, iDuration, szReason, szReasonAdminOnly, szAdmin);
}

public native_ungag_user()
{
	new szIP[MAX_IP_LENGTH], szName[MAX_NAME_LENGTH], szAdmin[MAX_NAME_LENGTH];

	get_string(1, szName, charsmax(szName));
	get_string(2, szIP, charsmax(szIP));
	get_string(3, szAdmin, charsmax(szAdmin));

	if (!regex_match_c(szIP, g_iRegexIPPattern, g_iUnused))
	{
		log_error(AMX_ERR_NATIVE, "%s is not a valid IP Address!", szIP);
		return;
	}

	UngagUser(szName, szIP, szAdmin);
}

public native_ungag_id()
{
	new id;

	id = get_param(1);

	if (!is_user_connected(id))
	{
		log_error(AMX_ERR_NATIVE, "Invalid player ID %d", id);
		return;
	}

	new szAdmin[MAX_NAME_LENGTH], szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH];

	get_string(2, szAdmin, charsmax(szAdmin));

	get_user_name(id, szName, charsmax(szName));
	get_user_ip(id, szIP, charsmax(szIP), 1);

	UngagUser(szName, szIP, szAdmin);
}

public client_putinserver(id)
{
	static szExtraChecks[MAX_FMT_LENGTH];
	g_blIsUserMuted[id] = IsUserGagged(id, false) == GAG_YES;

	get_user_name(id, g_szName[id], charsmax(g_szName[]));
	get_user_ip(id, g_szIP[id], charsmax(g_szIP[]), 1);

	g_iSpamCount[id] = 0;

	copy(g_szPlayerLastMessage[id], charsmax(g_szPlayerLastMessage[]), "");
	copy(g_szLastSaidSpam[id], charsmax(g_szLastSaidSpam[]), "");

	if (get_user_flags(id) & ADMIN_IMMUNITY && gp_IgnoreAdmins_Immunity)
		return PLUGIN_CONTINUE;

	if (g_iTotalPhrases[BLACK] > 0)
	{
		for (new i = 0; i < g_iTotalPhrases[BLACK]; i++)
		{
			ArrayGetString(Array:g_aList[BLACK], i, szExtraChecks, charsmax(szExtraChecks));
			if (containi(g_szName[id], szExtraChecks) != -1 || equali(g_szName[id], szExtraChecks))
			{
				server_cmd("kick #%d ^"[%s] Bad words [%s] detected in name^"", get_user_userid(id), PLUGIN, szExtraChecks);
				return PLUGIN_HANDLED;
			}
		}
	}
	if (is_invalid(g_szName[id]))
	{
		server_cmd("kick #%d ^"[%s] IP/Site Pattern [%s] detected in name!^"", get_user_userid(id), PLUGIN, g_szName[id]);
		return PLUGIN_HANDLED;
	}
	return PLUGIN_HANDLED;
}

public Block_NameChange_OnGagDetect(msgid, msgdest, msgent)
{
	new s_MessageType[MAX_NAME_LENGTH];
	get_msg_arg_string(2, s_MessageType, charsmax(s_MessageType));

	if (equal(s_MessageType, "#Cstrike_Name_Change") && g_bForced_Name_Change)
	{
		g_bForced_Name_Change = false;
		return PLUGIN_HANDLED;
	}  
	return PLUGIN_CONTINUE;
}

public amx_menu_setgagtimes()
{
	new szBuffer[32];
	new szArgs = read_argc();
	
	if (szArgs <= 1)
	{
		server_print("usage: amx_menu_gag_times <time1> [time2] [time3] ...");
		server_print("   use time of 0 for permanent.");
		return;
	}
	
	ArrayClear(g_aGagTimes);
	
	for (new i = 1; i < szArgs; i++)
	{
		read_argv(i, szBuffer, charsmax(szBuffer));
		ArrayPushCell(g_aGagTimes, str_to_num(szBuffer));
	}
}
public amx_menu_setgagreasons()
{
	new szBuffer[MAX_REASON_LENGHT];
	new szArgs = read_argc();
	
	if (szArgs <= 1)
	{
		server_print("usage: amx_menu_gag_reasons <reason1> [reason2] [reason3] ...");
		server_print("   use reason of ^"Custom Reason^" for using custom reason.");
		return;
	}
	
	ArrayClear(g_aGagReason);
	
	for (new i = 1;  i < szArgs; i++)
	{
		read_argv(i, szBuffer, charsmax(szBuffer));
		ArrayPushString(g_aGagReason, szBuffer);
	}
	
}

public RG__CSGameRules_CanPlayerHearPlayer(iReceiver, iSender)
{
	if (iReceiver == iSender || !is_user_connected(iSender))
		return HC_CONTINUE;

	if (g_blIsUserMuted[iSender])
	{
		SetHookChainReturn(ATYPE_BOOL, false);
		return HC_SUPERCEDE;
	}

	return HC_CONTINUE;
}

public RG__CBasePlayer_SetClientUserInfoName(id, szInfoBuffer[], szNewName[])
{
	if (!is_user_connected(id) || get_user_flags(id) & ADMIN_IMMUNITY && gp_IgnoreAdmins_Immunity)
		return HC_CONTINUE;

	if (IsUserGagged(id, false) == GAG_YES)
	{
		SetHookChainReturn(ATYPE_BOOL, false);
		return HC_SUPERCEDE;
	}

	if (!equal(g_szName[id], szNewName))
	{
		copy(g_szName[id], charsmax(g_szName[]), szNewName);
		set_task(0.1, "Client_Update_Name", id, g_szName[id], sizeof(g_szName[]));
		SetHookChainReturn(ATYPE_BOOL, false);
		return HC_SUPERCEDE;
	}
	return HC_CONTINUE;
}

public Client_Update_Name(szName[], id)
{
	if (!is_user_connected(id))
		return PLUGIN_HANDLED;

	static szExtraChecks[MAX_NAME_LENGTH], szReason[MAX_NAME_LENGTH];

	if (IsUserGagged(id, false) == GAG_NOT)
	{
		if (g_iTotalPhrases[BLACK] > 0)
		{
			for (new i = 0; i < g_iTotalPhrases[BLACK]; i++)
			{
				ArrayGetString(Array:g_aList[BLACK], i, szExtraChecks, charsmax(szExtraChecks));
				if (containi(g_szName[id], szExtraChecks) != -1 || equali(g_szName[id], szExtraChecks))
				{
					copy(szReason, charsmax(szReason), szExtraChecks);
					g_bBadNameDetected = true;
					goto ForceNameChange;
				}
			}
		}
		
		if (is_invalid(g_szName[id]))
		{
			copy(szReason, charsmax(szReason), g_szName[id]);
			g_bBadNameDetected = true;
			goto ForceNameChange;
		}
	}

	ForceNameChange:
	if (g_iTotalPhrases[BAD_NAME_REPLACEMENTS] > 0 && g_bBadNameDetected)
	{
		new iRandomName = random_num(0, ArraySize(Array:g_aList[BAD_NAME_REPLACEMENTS]) - 1);
		ArrayGetString(Array:g_aList[BAD_NAME_REPLACEMENTS], iRandomName, szExtraChecks, charsmax(szExtraChecks));

		g_bForced_Name_Change = true;
		set_user_info(id, "name", szExtraChecks);
		copy(g_szName[id], charsmax(g_szName[]), szExtraChecks);

		set_task(0.1, "Delay_User_Gag", id, szReason, charsmax(szReason));
		return PLUGIN_HANDLED;
	}
	else
	{
		g_bForced_Name_Change = false;
		set_user_info(id, "name", szName);
		copy(g_szName[id], charsmax(g_szName[]), szName);
	}
	return PLUGIN_HANDLED;
}

public Delay_User_Gag(szReason[], id)
{
	if (!is_user_connected(id))
		return PLUGIN_HANDLED;

	GagUser(g_szName[id], g_szIP[id], gp_iAutoGagTime_BadName, gp_szReasonBadName, fmt("[%s]", szReason), gp_szAdminBadName);
	g_bBadNameDetected = false;
	g_bForced_Name_Change = false;
	return PLUGIN_HANDLED;
}

public RG__Entity_Think(iEnt)
{
	if (iEnt != g_iThinkingEnt || !gp_blEnableGagExpireMsg)
		return;

	static iPlayers[MAX_PLAYERS], iPlayersNum, id;
	get_players(iPlayers, iPlayersNum);

	for (--iPlayersNum; iPlayersNum >= 0; iPlayersNum--)
	{
		id = iPlayers[iPlayersNum];

		if (IsUserGagged(id, false) == GAG_EXPIRED)
		{
			static szName[MAX_NAME_LENGTH];
			get_user_name(id, szName, charsmax(szName));

			CC_SendMessage(0, "Player !t%s !nis no longer gagged!", szName);

			if (gp_blHudEnabled)
			{
				static szHudMessage[MAX_FMT_LENGTH];
				formatex(szHudMessage, charsmax(szHudMessage), "%s gag has expired", szName);
				rg_send_hudmessage(0, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0);
			}
		}
	}

	set_entvar(iEnt, var_nextthink, get_gametime() + 1.0);
}

public CommandSayExecuted(id)
{
	static szMessage[192], szExtraChecks[192];
	read_args(szMessage, charsmax(szMessage));
	remove_quotes(szMessage);

	copy(g_szPlayerLastMessage[id], charsmax(g_szPlayerLastMessage[]), fmt("\d[\y%s\d]", szMessage));

	if (IsUserGagged(id) == GAG_YES)
		return PLUGIN_HANDLED;

	if (get_user_flags(id) & ADMIN_IMMUNITY && gp_IgnoreAdmins_Immunity)
		return PLUGIN_CONTINUE;

	if (is_invalid(szMessage) && IsUserGagged(id, false) == GAG_NOT)
	{
		GagUser(g_szName[id], g_szIP[id], gp_iAutoGagTime_Advertise, fmt("%s", gp_szReasonAdvertise), gp_szReasonAdvertise, gp_szAdminAdvertise);
		return PLUGIN_HANDLED;
	}

	if (is_invalid(fmt("%n", id)) && IsUserGagged(id, false) == GAG_NOT)
	{
		GagUser(fmt("%n", id), g_szIP[id], gp_iAutoGagTime_BadName, gp_szReasonBadName, fmt("[%s]", g_szName[id]), gp_szAdminBadName);
		server_cmd("kick #%d ^"[%s] IP/Site Pattern [%s] detected in name!^"", get_user_userid(id), PLUGIN, g_szName[id]);
		return PLUGIN_HANDLED;
	}
	
	if (g_iTotalPhrases[BLACK] > 0 && IsUserGagged(id, false) == GAG_NOT)
	{
		for (new i = 0; i < g_iTotalPhrases[BLACK]; i++)
		{
			ArrayGetString(Array:g_aList[BLACK], i, szExtraChecks, charsmax(szExtraChecks));
			if (containi(szMessage, szExtraChecks) != -1 || equali(szMessage, szExtraChecks))
			{
				GagUser(g_szName[id], g_szIP[id], gp_iAutoGagTime_BadWords, gp_szReasonBadWords, fmt("[%s]", szMessage), gp_szAdminBadWords);
				return PLUGIN_HANDLED;
			}
		}
	}

	if (g_iTotalPhrases[WHITE] > 0 && IsUserGagged(id, false) == GAG_YES)
	{
		for (new i = 0; i < g_iTotalPhrases[WHITE]; i++)
		{
			ArrayGetString(Array:g_aList[WHITE], i, szExtraChecks, charsmax(szExtraChecks));
			if (equal(szMessage, szExtraChecks))
			{
				return PLUGIN_CONTINUE;
			}
		}
	}

	if (is_user_spamming(id, szMessage) && IsUserGagged(id, false) == GAG_NOT)
	{
		return PLUGIN_CONTINUE;
	}

	return PLUGIN_CONTINUE;
}

bool:is_user_spamming(const id, const szSpamMessage[])
{
	if (equal(g_szLastSaidSpam[id], szSpamMessage))
	{
		if (++g_iSpamCount[id] >= gp_iSpamCount)
		{
			GagUser(g_szName[id], g_szIP[id], gp_iAutoGagTime_SpamChat, gp_szReasonSpamChat, fmt("Spam: %s", g_szLastSaidSpam[id]), gp_szAdminSpamChat);
			return true;
		}
	}
	else
	{
		g_iSpamCount[id] = 0;
		copy(g_szLastSaidSpam[id], charsmax(g_szLastSaidSpam[]), szSpamMessage);
	}
	return false;
}

public CommandGag(id, iLevel, iCmdId)
{
	if (!cmd_access(id, iLevel, iCmdId, 4))
		return PLUGIN_HANDLED;

	new szTarget[MAX_PLAYERS], szTargetIP[MAX_IP_LENGTH], szTime[8], szReason[MAX_REASON_LENGHT], szReasonAdminOnly[MAX_REASON_LENGHT];
	read_argv(1, szTarget, charsmax(szTarget));

	if (!regex_match_c(szTarget, g_iRegexIPPattern, g_iUnused))
	{
		new iTarget = cmd_target(id, szTarget);

		if (!iTarget)
			return PLUGIN_HANDLED;

		get_user_name(iTarget, szTarget, charsmax(szTarget));
		get_user_ip(iTarget, szTargetIP, charsmax(szTargetIP), 1);
		g_blIsUserMuted[iTarget] = true;
	}
	else
	{
		copy(szTargetIP, charsmax(szTargetIP), szTarget);
	}

	read_argv(2, szTime, charsmax(szTime));
	read_argv(3, szReason, charsmax(szReason));
	read_argv(4, szReasonAdminOnly, charsmax(szReasonAdminOnly));
	new iTime = str_to_num(szTime);

	new szAdmin[MAX_NAME_LENGTH];
	get_user_name(id, szAdmin, charsmax(szAdmin));

	console_print(id, "%s", GagUser(szTarget, szTargetIP, iTime, szReason, szReasonAdminOnly, szAdmin));

	return PLUGIN_HANDLED;
}

public CommandUngag(id, iLevel, iCmdId)
{
	if (!cmd_access(id, iLevel, iCmdId, 2))
		return PLUGIN_HANDLED;

	new szTarget[MAX_PLAYERS], szTargetIP[MAX_IP_LENGTH];
	read_argv(1, szTarget, charsmax(szTarget));

	if (!regex_match_c(szTarget, g_iRegexIPPattern, g_iUnused))
	{
		new iTarget = cmd_target(id, szTarget, CMDTARGET_ALLOW_SELF);

		if (!iTarget)
			return PLUGIN_HANDLED;

		get_user_name(iTarget, szTarget, charsmax(szTarget));
		get_user_ip(iTarget, szTargetIP, charsmax(szTargetIP), 1);
	}
	else
	{
		copy(szTargetIP, charsmax(szTargetIP), szTarget);
	}

	new szAdminName[MAX_NAME_LENGTH];
	get_user_name(id, szAdminName, charsmax(szAdminName));

	console_print(id, "%s", UngagUser(szTarget, szTargetIP, szAdminName));

	return PLUGIN_HANDLED;
}

public actionGagMenu(id, iKey)
{
	switch (iKey)
	{
		case 6:
		{
			new szReasons[MAX_REASON_LENGHT];
			
			++g_iMenuReasonOption[id];
			g_iMenuReasonOption[id] %= ArraySize(g_aGagReason);
			
			ArrayGetString(g_aGagReason, g_iMenuReasonOption[id], szReasons, charsmax(szReasons));
			copy(g_iMenuSettingsReason[id], charsmax(g_iMenuSettingsReason[]), szReasons);
			
			displayGagMenu(id, g_iMenuPosition[id]);
		}
		case 7:
		{
			++g_iMenuOption[id];
			g_iMenuOption[id] %= ArraySize(g_aGagTimes);
			
			g_iMenuSettings[id] = ArrayGetCell(g_aGagTimes, g_iMenuOption[id]);
			
			displayGagMenu(id, g_iMenuPosition[id]);
		}
		case 8:
		{
			displayGagMenu(id, ++g_iMenuPosition[id]);
		}
		case 9:
		{
			displayGagMenu(id, --g_iMenuPosition[id]);
		}
		default:
		{
			g_iGagTime = g_iMenuSettings[id];
			
			new szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH], szAdminName[MAX_NAME_LENGTH];
			g_iUserTarget[id] = g_iMenuPlayers[id][g_iMenuPosition[id] * 6 + iKey];

			if (~get_user_flags(id) & (ADMIN_KICK | ADMIN_RCON) && g_iGagTime <= 0 && IsUserGagged(g_iUserTarget[id], false) == GAG_NOT)
			{
				client_print(id, print_center, "You have no access to that command!");
				displayGagMenu(id, g_iMenuPosition[id]);
				return PLUGIN_HANDLED;
			}

			if (get_user_flags(g_iUserTarget[id]) & ADMIN_IMMUNITY && !(get_user_flags(id) & ADMIN_RCON) && IsUserGagged(g_iUserTarget[id], false) == GAG_NOT
				|| get_user_flags(g_iUserTarget[id]) & (ADMIN_IMMUNITY & ADMIN_RCON))
			{
				client_print(id, print_center, "You can't gag this user due to his/her immunity..");
				displayGagMenu(id, g_iMenuPosition[id]);
				return PLUGIN_HANDLED;
			}

			if (!(get_user_flags(id) & ADMIN_CFG) && IsUserGagged(g_iUserTarget[id], false) == GAG_YES)
			{
				client_print(id, print_center, "You have no access to ungag players!");
				displayGagMenu(id, g_iMenuPosition[id]);
				return PLUGIN_HANDLED;
			}

			get_user_name(id, szAdminName, charsmax(szAdminName));
			get_user_name(g_iUserTarget[id], szName, charsmax(szName));
			get_user_ip(g_iUserTarget[id], szIP, charsmax(szIP), 1);
			
			if (IsUserGagged(g_iUserTarget[id], false) == GAG_YES)
			{
				UngagUser(szName, szIP, szAdminName);
				displayGagMenu(id, g_iMenuPosition[id]);
			}
			else
			{
				if (equal(g_iMenuSettingsReason[id], "Custom Reason") || g_iMenuSettingsReason[id][0] == EOS)
				{
					client_cmd(id, "messagemode amx_TYPE_GAGREASON");
					CC_SendMessage(id, "Type in the !treason!n, or !g!cancel !nto cancel.");
				}
				else
				{
					GagUser(szName, szIP, g_iGagTime, g_iMenuSettingsReason[id], "Gag by Menu", szAdminName);
					g_blIsUserMuted[g_iUserTarget[id]] = true;
				}
			}
		}
	}
	return PLUGIN_HANDLED;
}

displayGagMenu(id, iPos)
{
	if (iPos < 0)
		return;
	
	get_players(g_iMenuPlayers[id], g_iMenuPlayersNum[id]);

	new szMenu[MAX_MENU_LENGTH], i, szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH];
	new b = 0;
	new iStart = iPos * 6;
	
	if (iStart >= g_iMenuPlayersNum[id])
	{
		iStart = iPos = g_iMenuPosition[id] = 0;
	}
	
	new iLen = formatex(szMenu, charsmax(szMenu), "\wGag\d/\yUngag \rMenu\R%d/%d^n\w^n", iPos + 1, (g_iMenuPlayersNum[id] / 6 + ((g_iMenuPlayersNum[id] % 6) ? 1 : 0)));
	new iEnd = iStart + 6;
	new iKeys = MENU_KEY_0|MENU_KEY_7|MENU_KEY_8;
	
	if (iEnd > g_iMenuPlayersNum[id])
	{
		iEnd = g_iMenuPlayersNum[id];
	}
	
	for (new a = iStart; a < iEnd; ++a)
	{
		i = g_iMenuPlayers[id][a];
		get_user_name(i, szName, charsmax(szName));
		get_user_ip(i, szIP, charsmax(szIP), 1);
		
		if (is_user_bot(i) || (access(i, ADMIN_IMMUNITY) && i != id))
		{
			++b;
			
			if (get_user_flags(i) & ADMIN_IMMUNITY)
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d%i. %s \r[\wHas immunity\r]^n\w", b, szName);
			else
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d%i. %s^n\w", b, szName);
		}
		else
		{
			iKeys |= (1<<b);

			if (is_user_admin(i))
			{
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "%i. %s%s \r* %s %s^n\w", ++b, IsUserGagged(i, false) ? "\y" : "\w", szName, GetGaggedPlayerInfo(szIP), IsUserGagged(i, false) ? GetGaggedPlayerInfo_Reason(szIP) : g_szPlayerLastMessage[i]);
			}
			else
			{
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen,  "%i. %s%s %s %s^n\w", ++b, IsUserGagged(i, false) ? "\y" : "\w", szName, GetGaggedPlayerInfo(szIP), IsUserGagged(i, false) ? GetGaggedPlayerInfo_Reason(szIP) : g_szPlayerLastMessage[i]);
			}
		}
	}
	
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen,  "^n7. Gag reason: %s%s\w", equal(g_iMenuSettingsReason[id], "Custom Reason") ? "\r" : "\y", g_iMenuSettingsReason[id]);
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, g_iMenuSettings[id] ? "^n8. Gag for \y%i minutes\w^n" : "^n8. Gag \rpermanently\w^n", g_iMenuSettings[id]);
	
	if (iEnd != g_iMenuPlayersNum[id])
	{
		formatex(szMenu[iLen], charsmax(szMenu) - iLen,  "^n9. More...^n0. %s", iPos ? "Back" : "Exit");
		iKeys |= MENU_KEY_9;
	}
	else
	{
		formatex(szMenu[iLen], charsmax(szMenu) - iLen,  "^n0. %s", iPos ? "Back" : "Exit");
	}

	show_menu(id, iKeys, szMenu, -1, "Gag Menu");
}

public CommandGagReason(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1) || !is_user_connected(g_iUserTarget[id]))
		return PLUGIN_HANDLED;
	
	new szReason[MAX_REASON_LENGHT], szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH], szAdminName[MAX_NAME_LENGTH];
	read_argv(1, szReason, charsmax(szReason));
	
	if (equali(szReason, "!cancel"))
	{
		displayGagMenu(id, g_iMenuPosition[id]);
		return PLUGIN_HANDLED;
	}

	get_user_name(id, szAdminName, charsmax(szAdminName));
	get_user_name(g_iUserTarget[id], szName, charsmax(szName));
	get_user_ip(g_iUserTarget[id], szIP, charsmax(szIP), 1);

	GagUser(szName, szIP, g_iGagTime, szReason, "Gag by Menu", szAdminName);
	g_blIsUserMuted[g_iUserTarget[id]] = true;
	return PLUGIN_HANDLED;
}

public cmdGagMenu(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED;

	g_iMenuOption[id] = 0;
	g_iMenuReasonOption[id] = 0;
	g_iUserTarget[id] = 0;

	if (ArraySize(g_aGagTimes) > 0)
	{
		g_iMenuSettings[id] = ArrayGetCell(g_aGagTimes, g_iMenuOption[id]);
	}
	else
	{
		// should never happen, but failsafe
		g_iMenuSettings[id] = 0;
	}
	
	if (ArraySize(g_aGagReason) > 0)
	{
		new szReasons[MAX_REASON_LENGHT];
			
		ArrayGetString(g_aGagReason, g_iMenuReasonOption[id], szReasons, charsmax(szReasons));
		copy(g_iMenuSettingsReason[id], charsmax(g_iMenuSettingsReason[]), szReasons);
	}
	else
	{
		// should never happen, but failsafe
		copy(g_iMenuSettingsReason[id], charsmax(g_iMenuSettingsReason[]), "Custom Reason");
	}
	displayGagMenu(id, g_iMenuPosition[id] = 0);

	return PLUGIN_HANDLED;
}

public CommandCleanDB(id, iLevel, iCmdId)
{
	if (!cmd_access(id, iLevel, iCmdId, 1))
	{
		return PLUGIN_HANDLED;
	}

	nvault_prune(g_iNVaultHandle, 0, get_systime());

	console_print(id, "Database has been cleaned.");

	return PLUGIN_HANDLED;
}

UngagUser(szName[], szIP[], szAdmin[])
{
	new szResult[64], szTemp[3];

	if (!nvault_get(g_iNVaultHandle, szIP, szTemp, charsmax(szTemp)))
	{
		formatex(szResult, charsmax(szResult), "User with IP %s not found.", szIP);
		return szResult;
	}

	nvault_remove(g_iNVaultHandle, szIP);

	if (!equal(szName, szIP))
	{
		new iTarget = cmd_target(0, szName, 0);

		g_blIsUserMuted[iTarget] = false;

		CC_SendMessage(iTarget, "You have been ungagged by admin !t%s!n!", szAdmin);

		CC_SendMessage(0, "Player !t%s !nhas been ungagged by !g%s!n.", szName, szAdmin);

		if (gp_blHudEnabled)
		{
			new szHudMessage[MAX_FMT_LENGTH];
			formatex(szHudMessage, charsmax(szHudMessage), "%s has been ungagged by %s", szName, szAdmin);
			rg_send_hudmessage(0, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0);
		}
	}

	new id = find_player("d", szIP);
	if (id != 0)
	{
		g_iSpamCount[id] = 0;
		ExecuteForward(g_UngagForward, g_iUnused, id);
	}

	#if defined LOG_GAGS
	log_to_file(g_szLogFile, "[UNGAG] ADMIN: %s | TARGET_NAME: %s [IP: %s]", szAdmin, szName, szIP);
	#endif
	copy(szResult, charsmax(szResult), "Player has been ungagged");
	return szResult;
}

GagUser(szName[], szIP[], iDuration, szReason[], szReasonAdminOnly[], szAdminName[])
{
	new iExpireTime = iDuration != 0 ? get_systime() + (iDuration * 60) : 0;

	new szResult[64];

	if (nvault_get(g_iNVaultHandle, szIP, szResult, charsmax(szResult)))
	{
		copy(szResult, charsmax(szResult), "Player is already gagged.");
		return szResult;
	}

	new szValue[512];
	formatex(szValue, charsmax(szValue), "^"%s^"#^"%s^"#^"%s^"#%d#^"%s^"", szName, szReason, szReasonAdminOnly, iExpireTime, szAdminName);

	if (iExpireTime == 0)
	{
		CC_SendMessage(0, "Player!t %s!n has been gagged by!g %s!n. Reason: !t%s!n. Gag expires!t never!n.", szName, szAdminName, szReason);

		if (gp_blHudEnabled)
		{
			new szHudMessage[MAX_FMT_LENGTH];
			formatex(szHudMessage, charsmax(szHudMessage), "%s has been gagged by %s^nExpires: Never^nReason: %s", szName, szAdminName, szReason);
			rg_send_hudmessage(0, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0);
		}
	}
	else
	{
		CC_SendMessage(0, "Player!t %s!n has been gagged by!g %s!n. Reason: !t%s!n. Gag expires!t %s", szName, szAdminName, szReason, GetTimeAsString(iDuration * 60));

		if (gp_blHudEnabled)
		{
			new szHudMessage[MAX_FMT_LENGTH];
			formatex(szHudMessage, charsmax(szHudMessage), "%s has been gagged by %s^nExpires in %s^nReason: %s", szName, szAdminName, GetTimeAsString(iDuration * 60), szReason);
			rg_send_hudmessage(0, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0);
		}
	}
	
	emit_sound(0, CHAN_AUTO, g_szGagSound, 1.0, ATTN_NORM, SND_SPAWNING, PITCH_NORM);
	

	#if defined LOG_GAGS
	log_to_file(g_szLogFile, "ADMIN: %s | PLAYER: %s [IP: %s] | REASON: %s | TIME: %s", szAdminName, szName, szIP, szReason, GetTimeAsString(iDuration * 60));
	#endif
	

	new id = find_player("d", szIP);

	if (id != 0)
	{
		ExecuteForward(g_GagForward, g_iUnused, id);
	}
	
	nvault_set(g_iNVaultHandle, szIP, szValue);
	
	copy(szResult, charsmax(szResult), "Player successfully gagged.");
	return szResult;
}

IsUserGagged(id, bool:print = true)
{
	new szIP[MAX_IP_LENGTH], szVaultData[512];
	get_user_ip(id, szIP, charsmax(szIP), 1);

	if (!nvault_get(g_iNVaultHandle, szIP, szVaultData, charsmax(szVaultData)))
	{
		g_blIsUserMuted[id] = false;
		return GAG_NOT;
	}

	new szGaggedName[MAX_NAME_LENGTH], szReason[MAX_REASON_LENGHT], szReasonAdminOnly[MAX_REASON_LENGHT], szExpireDate[32], szAdminName[MAX_NAME_LENGTH];
	replace_all(szVaultData, charsmax(szVaultData), "#", " ");
	parse(szVaultData, szGaggedName, charsmax(szGaggedName), szReason, charsmax(szReason), szReasonAdminOnly, charsmax(szReasonAdminOnly), szExpireDate, charsmax(szExpireDate), szAdminName, charsmax(szAdminName));

	new iExpireTime = str_to_num(szExpireDate);

	if (get_systime() < iExpireTime || iExpireTime == 0)
	{
		if (print)
		{
			if (iExpireTime == 0)
			{
				CC_SendMessage(id, "You are gagged! Your gag expires!t never!n.");
			}
			else
			{
				CC_SendMessage(id, "You are gagged! Your gag expires in!t %s", GetTimeAsString(iExpireTime - get_systime()));
			}

			CC_SendMessage(id, "Gagged by!g %s!n. Gagged nickname:!t %s!n. Gag reason:!t %s !n| !t%s!n.", szAdminName, szGaggedName, szReason, szReasonAdminOnly);
		}

		g_blIsUserMuted[id] = true;

		return GAG_YES;
	}

	g_blIsUserMuted[id] = false;
	ExecuteForward(g_UngagForward, g_iUnused, id);

	nvault_remove(g_iNVaultHandle, szIP);

	return GAG_EXPIRED;
}

stock GetGaggedPlayerInfo(const iPlayerIP[])
{
	new szGaggedName[MAX_NAME_LENGTH], szReason[MAX_REASON_LENGHT], szReasonAdminOnly[MAX_REASON_LENGHT], szExpireDate[32], szAdminName[MAX_NAME_LENGTH], szGagTimeLeft[64], szVaultData[512];

	if (!nvault_get(g_iNVaultHandle, iPlayerIP, szVaultData, charsmax(szVaultData)))
	{
		formatex(szGagTimeLeft, charsmax(szGagTimeLeft), "");
	}
	else
	{
		replace_all(szVaultData, charsmax(szVaultData), "#", " ");
		parse(szVaultData, szGaggedName, charsmax(szGaggedName), szReason, charsmax(szReason), szReasonAdminOnly, charsmax(szReasonAdminOnly), szExpireDate, charsmax(szExpireDate), szAdminName, charsmax(szAdminName));

		new iExpireTime = str_to_num(szExpireDate);

		if (get_systime() < iExpireTime || iExpireTime == 0)
		{
			if (iExpireTime == 0)
				formatex(szGagTimeLeft, charsmax(szGagTimeLeft), "\dExpire: \rNever");
			else
				formatex(szGagTimeLeft, charsmax(szGagTimeLeft), "\dExpire: \r%s", GetTimeAsString(iExpireTime - get_systime()));
		}
	}
	return szGagTimeLeft;
}

stock GetGaggedPlayerInfo_Reason(const iPlayerIP[])
{
	new szGaggedName[MAX_NAME_LENGTH], szReason[MAX_REASON_LENGHT], szReasonAdminOnly[MAX_REASON_LENGHT], szExpireDate[32], szAdminName[MAX_NAME_LENGTH], szVaultData[512], szReasonFmt[MAX_REASON_LENGHT];

	if (!nvault_get(g_iNVaultHandle, iPlayerIP, szVaultData, charsmax(szVaultData)))
	{
		formatex(szReason, charsmax(szReason), "");
	}
	else
	{
		replace_all(szVaultData, charsmax(szVaultData), "#", " ");
		parse(szVaultData, szGaggedName, charsmax(szGaggedName), szReason, charsmax(szReason), szReasonAdminOnly, charsmax(szReasonAdminOnly), szExpireDate, charsmax(szExpireDate), szAdminName, charsmax(szAdminName));
		
		formatex(szReasonFmt, charsmax(szReasonFmt), "\d[\y%s \d| \r%s\d]", szReason, szReasonAdminOnly);
	}
	return szReasonFmt;
}

GetTimeAsString(seconds)
{
	new iYears = seconds / 31536000;
	seconds %= 31536000;

	new iMonths = seconds / 2592000;
	seconds %= 2592000;

	new iWeeks = seconds / 604800;
	seconds %= 604800;

	new iDays = seconds / 86400;
	seconds %= 86400;

	new iHours = seconds / 3600;
	seconds %= 3600;

	new iMinutes = seconds / 60;
	seconds %= 60;

	new szResult[256];

	if (iYears)
	{
		format(szResult, charsmax(szResult), "%s%d Year%s ", szResult, iYears, iYears == 1 ? "" : "s");
	}

	if (iMonths)
	{
		format(szResult, charsmax(szResult), "%s%d Month%s ", szResult, iMonths, iMonths == 1 ? "" : "s");
	}

	if (iWeeks)
	{
		format(szResult, charsmax(szResult), "%s%d Week%s ", szResult, iWeeks, iWeeks == 1 ? "" : "s");
	}

	if (iDays)
	{
		format(szResult, charsmax(szResult), "%s%d Day%s ", szResult, iDays, iDays == 1 ? "" : "s");
	}

	if (iHours)
	{
		format(szResult, charsmax(szResult), "%s%d Hour%s ", szResult, iHours, iHours == 1 ? "" : "s");
	}

	if (iMinutes)
	{
		format(szResult, charsmax(szResult), "%s%d Minute%s ", szResult, iMinutes, iMinutes == 1 ? "" : "s");
	}

	if (seconds)
	{
		format(szResult, charsmax(szResult), "%s%d Second%s", szResult, seconds, seconds == 1 ? "" : "s");
	}

	return szResult;
}

bool:is_invalid(const text[])
{
	new error[50], num;
	new Regex:regex = regex_match(text, "\b(?:\d{1,3}(\,|\<|\>|\~|\«|\»|\=|\.|\s|\*|\')){3}\d{1,3}\b", num, error, charsmax(error), "i");
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}
	regex = regex_match(text, "([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){2}", num, error, charsmax(error));
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}
	
	regex = regex_match(text, "([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}", num, error, charsmax(error));
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}
	
	regex = regex_match(text, "[a-zA-Z0-9\-\.]+\.(com|org|net|bg|info|COM|ORG|NET|BG|INFO)", num, error, charsmax(error));
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}
	
	regex = regex_match(text, "(?:\w+\.[a-z]{2,4}\b|(?:\s*\d+\s*\.){3})", num, error, charsmax(error));
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}

	return false;
}