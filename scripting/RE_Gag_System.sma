#include <amxmodx>
#include <amxmisc>
#include <reapi_stocks>
#include <regex>
#include <nvault>

#define CC_COLORS_TYPE CC_COLORS_SHORT
#include <cromchat>

#pragma semicolon 1
#pragma dynamic 32768

#define PLUGIN "RE: Gag System"
#define VERSION "1.6"

#define LOG_GAGS
#define MAX_REASON_LENGHT 64
#define IP_PATTERN "([0-9]+.*[1-9][0-9]+.*[0-9]+.*[0-9])"

// Uncomment any of the modules you would like to use!
//#define GRIP_MODULE
//#define CURL_MODULE

/* ** NOTE ** 
	Better to use CURL Module instead of GRIP
   **	   **
*/

#if defined GRIP_MODULE || defined CURL_MODULE
// You must create WebHook in channel you want the gag system to send the information..
new const DISCORD_WEBHOOK[] = "https://discord.com/api/webhooks/";
#endif

#if defined GRIP_MODULE
#include <grip>
new const DISCORD_REPORT_GRIP[] = ":grey_exclamation: `GAG Report` :grey_exclamation:^n```python^nADMIN NAME: {admin} ({adminid})^nTARGET: {target} ({targetid}) ({targetip})^nTIME: {time}^nREASON: {reason}^nACTION TYPE: {actiontype}```"; //What will be written in the discord channel
#endif

#if defined CURL_MODULE
#include <curl>

#define SERVER_NAME "Your Server Name Here"
#define SERVER_URL "Example GameTracker URL Here"
#define SERVER_IP "Your Server IP Here"
#define THUMBNAIL "https://avatars.githubusercontent.com/u/83426246?v=4" // Your Thumbnail avatar here [This one is mine from the github]
#define BANNER	"Your GameTracker.RS URL Banner image Here"

#define CURL_BUFFER_SIZE 4096

// To retrieve mention role you have to copy role id from discord and pasting it here. The role syntax is <@&RoleID> Example: <@&111111111111111111>																								
#define MENTION_ROLE "<@&RoleID>"

#endif

enum _:eDiscordData
{
	ADMIN_NAME[MAX_NAME_LENGTH],
	ADMIN_ID[MAX_AUTHID_LENGTH],
	PLAYER_NAME[MAX_NAME_LENGTH],
	PLAYER_ID[MAX_AUTHID_LENGTH],
	PLAYER_IP[MAX_IP_LENGTH],
	GAG_TIME[MAX_REASON_LENGHT],
	GAG_REASON[MAX_REASON_LENGHT],
	GAG_ACTION[MAX_NAME_LENGTH]
};

new g_szDiscordReplacements[eDiscordData];

enum _:GagState
{
	GAG_NOT,
	GAG_YES,
	GAG_EXPIRED
};

new const g_szVaultName[] = "re_gag_system";
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
	BAD_NAMES,
	BAD_NAME_REPLACEMENTS
}
new Array:g_aList[eLists], g_iTotalPhrases[eLists];
new g_szName[MAX_PLAYERS + 1][MAX_NAME_LENGTH], g_szIP[MAX_PLAYERS + 1][MAX_IP_LENGTH];

// New cvar settings
enum eCvars
{
	CHAT_PREFIX[MAX_NAME_LENGTH],

	HUD_SHOW,
	PRINT_EXPIRED,
	AUTOGAG_ADMIN_IMMUNITY,

	AUTOGAG_BAD_WORDS,
	AUTOGAG_TIME_BAD_WORDS,
	AUTOGAG_ADMIN_BAD_WORDS[MAX_NAME_LENGTH],
	AUTOGAG_REASON_BAD_WORDS[MAX_NAME_LENGTH],

	AUTOGAG_ADVERTISE,
	AUTOGAG_TIME_ADVERTISE,
	AUTOGAG_ADMIN_ADVERTISE[MAX_NAME_LENGTH],
	AUTOGAG_REASON_ADVERTISE[MAX_NAME_LENGTH],

	AUTOGAG_BAD_NAMES,
	AUTOGAG_TIME_BAD_NAMES,
	AUTOGAG_ADMIN_BAD_NAMES[MAX_NAME_LENGTH],
	AUTOGAG_REASON_BAD_NAMES[MAX_NAME_LENGTH],

	AUTOGAG_SPAM_CHAT,
	AUTOGAG_TIME_SPAM_CHAT,
	AUTOGAG_ADMIN_SPAM_CHAT[MAX_NAME_LENGTH],
	AUTOGAG_REASON_SPAM_CHAT[MAX_NAME_LENGTH],
	AUTOGAG_SPAM_COUNT
};

new g_pCvarSetting[eCvars];

new g_szPlayerLastMessage[MAX_PLAYERS + 1][192];

new g_iSpamCount[MAX_PLAYERS + 1], g_szLastSaidSpam[MAX_PLAYERS + 1][192];

new bool:g_bForced_Name_Change, bool:g_bBadNameDetected;

new bool:g_bPlayerShuwHudMessage[MAX_PLAYERS + 1], g_szCustomTime_Reason[MAX_REASON_LENGHT];

enum eFileNames
{
	F_BLACKLIST, F_WHITELIST, F_BAD_NAMES, F_BAD_NAME_REPLACEMENTS, F_SETTINGS
};

new const g_szFileNames[eFileNames][] =
{
	"RGS_BlackList",
	"RGS_WhiteList",
	"RGS_Bad_Names",
	"RGS_Bad_Name_Replacements",
	"RGS_Settings"
};

new const g_szFolderName[] = "RE_Gag_System";


public plugin_init()
{
	register_plugin(PLUGIN, VERSION, "Huehue");
	register_cvar("re_gagsystem_amxxbg", VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED);

	register_clcmd("say", "CommandSayExecuted");
	register_clcmd("say_team", "CommandSayExecuted");

	g_GagForward = CreateMultiForward("user_gagged", ET_IGNORE, FP_CELL);
	g_UngagForward = CreateMultiForward("user_ungagged", ET_IGNORE, FP_CELL);

	bind_pcvar_string(create_cvar("regs_chat_prefix", "!g[RE: GagSystem]!n", FCVAR_NONE, "Prefix to show before chat messages"), g_pCvarSetting[CHAT_PREFIX], charsmax(g_pCvarSetting[CHAT_PREFIX]));

	bind_pcvar_num(create_cvar("regs_show_hud", "1", FCVAR_NONE, "Enables/Disables the hud messages", true, 0.0, true, 1.0), g_pCvarSetting[HUD_SHOW]);
	bind_pcvar_num(create_cvar("regs_print_expired", "1", FCVAR_NONE, "Enables/Disables the messages when gag expire", true, 0.0, true, 1.0), g_pCvarSetting[PRINT_EXPIRED]);
	bind_pcvar_num(create_cvar("regs_immunity_autogags", "1", FCVAR_NONE, "Enables/Disables the admin immunity for auto gags part", true, 0.0, true, 1.0), g_pCvarSetting[AUTOGAG_ADMIN_IMMUNITY]);
	
	// Bad Words
	bind_pcvar_num(create_cvar("regs_autogag_bad_words_check", "1", FCVAR_NONE, "Whether to check for bad words from the file or not", true, 0.0, true, 1.0), g_pCvarSetting[AUTOGAG_BAD_WORDS]);
	bind_pcvar_num(create_cvar("regs_autogag_time_bad_words", "5", FCVAR_NONE, "How many minutes gag will be applied when player uses words from blacklist"), g_pCvarSetting[AUTOGAG_TIME_BAD_WORDS]);
	bind_pcvar_string(create_cvar("regs_autogag_admin_name_bad_words", "AutoGag_BLW", FCVAR_NONE, "What name will be shown as administrator when player is gagged using blacklist words"), g_pCvarSetting[AUTOGAG_ADMIN_BAD_WORDS], charsmax(g_pCvarSetting[AUTOGAG_ADMIN_BAD_WORDS]));
	bind_pcvar_string(create_cvar("regs_autogag_reason_bad_words", "BlackList Words Detected", FCVAR_NONE, "What reason will be shown as gag when player is gagged using blacklist words"), g_pCvarSetting[AUTOGAG_REASON_BAD_WORDS], charsmax(g_pCvarSetting[AUTOGAG_REASON_BAD_WORDS]));
	
	// Advertise
	bind_pcvar_num(create_cvar("regs_autogag_advertise_check", "1", FCVAR_NONE, "Whether to check for ip/sites pattern or not", true, 0.0, true, 1.0), g_pCvarSetting[AUTOGAG_ADVERTISE]);
	bind_pcvar_num(create_cvar("regs_autogag_time_advertise", "5", FCVAR_NONE, "How many minutes gag will be applied when player uses ip/sites pattern"), g_pCvarSetting[AUTOGAG_TIME_ADVERTISE]);
	bind_pcvar_string(create_cvar("regs_autogag_admin_name_regex", "AutoGag_RGXP", FCVAR_NONE, "What name will be shown as administrator when player is gagged using ip/sites pattern"), g_pCvarSetting[AUTOGAG_ADMIN_ADVERTISE], charsmax(g_pCvarSetting[AUTOGAG_ADMIN_ADVERTISE]));
	bind_pcvar_string(create_cvar("regs_autogag_reason_regex", "Regex Pattern Detected", FCVAR_NONE, "What reason will be shown as gag when player is gagged using ip/sites pattern"), g_pCvarSetting[AUTOGAG_REASON_ADVERTISE], charsmax(g_pCvarSetting[AUTOGAG_REASON_ADVERTISE]));
	
	// Bad Names
	bind_pcvar_num(create_cvar("regs_autogag_bad_names_check", "1", FCVAR_NONE, "Whether to check names for ip/sites pattern, blacklist or not", true, 0.0, true, 1.0), g_pCvarSetting[AUTOGAG_BAD_NAMES]);
	bind_pcvar_num(create_cvar("regs_autogag_time_bad_name", "5", FCVAR_NONE, "How many minutes gag will be applied when player uses ip/sites/bad words pattern in name"), g_pCvarSetting[AUTOGAG_TIME_BAD_NAMES]);
	bind_pcvar_string(create_cvar("regs_autogag_admin_name_bad_name", "AutoGag_BN", FCVAR_NONE, "What name will be shown as administrator when player is gagged using ip/sites/bad words pattern"), g_pCvarSetting[AUTOGAG_ADMIN_BAD_NAMES], charsmax(g_pCvarSetting[AUTOGAG_ADMIN_BAD_NAMES]));
	bind_pcvar_string(create_cvar("regs_autogag_reason_bad_name", "Bad Name Detected", FCVAR_NONE, "What reason will be shown as gag when player is gagged using ip/sites/bad words pattern"), g_pCvarSetting[AUTOGAG_REASON_BAD_NAMES], charsmax(g_pCvarSetting[AUTOGAG_REASON_BAD_NAMES]));

	// Spam Chat
	bind_pcvar_num(create_cvar("regs_autogag_spam_chat_check", "1", FCVAR_NONE, "Whether to check for spam in chat or not", true, 0.0, true, 1.0), g_pCvarSetting[AUTOGAG_SPAM_CHAT]);
	bind_pcvar_num(create_cvar("regs_autogag_time_spam_chat", "5", FCVAR_NONE, "How many minutes gag will be applied when player uses same messages in a row in the chat"), g_pCvarSetting[AUTOGAG_TIME_SPAM_CHAT]);
	bind_pcvar_num(create_cvar("regs_autogag_spam_count", "3", FCVAR_NONE, "How many messages will count as spam when repeated again and again"), g_pCvarSetting[AUTOGAG_SPAM_COUNT]);
	bind_pcvar_string(create_cvar("regs_autogag_admin_name_spam_chat", "AutoGag_SC", FCVAR_NONE, "What name will be shown as administrator when player is gagged spamming in chat"), g_pCvarSetting[AUTOGAG_ADMIN_SPAM_CHAT], charsmax(g_pCvarSetting[AUTOGAG_ADMIN_SPAM_CHAT]));
	bind_pcvar_string(create_cvar("regs_autogag_reason_spam_chat", "Spam Chat Detected", FCVAR_NONE, "What reason will be shown as gag when player is gagged spamming in chat"), g_pCvarSetting[AUTOGAG_REASON_SPAM_CHAT], charsmax(g_pCvarSetting[AUTOGAG_REASON_SPAM_CHAT]));

	RegisterHookChain(RG_CSGameRules_CanPlayerHearPlayer, "RG__CSGameRules_CanPlayerHearPlayer");
	RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "RG__CBasePlayer_SetClientUserInfoName");

	register_clcmd("amx_gag", "Command_Gag", ADMIN_SLAY, "<name | #id | ip> <time> <reason> <admin reason>");
	register_clcmd("amx_ungag", "Command_UnGag", ADMIN_SLAY, "<name | #id | ip>");
	register_clcmd("amx_gagmenu", "Command_GagMenu", ADMIN_SLAY, "- displays gag/ungag menu");
	register_clcmd("REGS_TYPE_GAG_REASON", "Command_GagReason", ADMIN_SLAY);
	register_clcmd("REGS_TYPE_GAG_TIME", "Command_GagTime", ADMIN_SLAY);

	register_clcmd("amx_cleangags", "Command_CleanDB", ADMIN_RCON);
	register_clcmd("amx_reload_file", "Command_ReloadFile", ADMIN_RCON, "<filename>^n*RGS_BlackList^n*RGS_WhiteList^n*RGS_Bad_Names^n*RGS_Bad_Names_Replacements^n*RGS_Settings^n");

	register_clcmd("say /gaghud", "Command_ToggleHudMesssages");
	register_clcmd("say_team /gaghud", "Command_ToggleHudMesssages");

	register_menucmd(register_menuid("Gag Menu"), 1023, "actionGagMenu");

	register_message(get_user_msgid("SayText"), "Block_NameChange_OnGagDetect");

	g_iRegexIPPattern = regex_compile_ex(IP_PATTERN);

	g_iNVaultHandle = nvault_open(g_szVaultName);

	if (g_iNVaultHandle == INVALID_HANDLE)
	{
		set_fail_state("Failed to open NVault DB!");
	}
	
	g_aGagTimes = ArrayCreate();
	ArrayPushCell(g_aGagTimes, 1914); // Custom gag time
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

	AutoExecConfig(true, g_szFileNames[F_SETTINGS], g_szFolderName);
}

public OnAutoConfigsBuffered()
{
	CC_SetPrefix(g_pCvarSetting[CHAT_PREFIX]);
}

public Command_ToggleHudMesssages(id)
{
	g_bPlayerShuwHudMessage[id] = !g_bPlayerShuwHudMessage[id];
	CC_SendMessage(id, "!tGag Hud Messages !nswitched to !g%s !nmode!", g_bPlayerShuwHudMessage[id] ? "display" : "no display");
	return PLUGIN_HANDLED;
}

public plugin_precache()
{
	precache_sound(g_szGagSound);

	g_aList[WHITE] = ArrayCreate(128, 1);
	g_aList[BLACK] = ArrayCreate(128, 1);
	g_aList[BAD_NAMES] = ArrayCreate(128, 1);
	g_aList[BAD_NAME_REPLACEMENTS] = ArrayCreate(32, 1);

	Load_BlackList();
	Load_WhiteList();
	Load_BadName_List();
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

public Load_BadName_List()
{
	static szConfigsDir[128], iFile, szBadName_List[128];
	get_configsdir(szConfigsDir, charsmax(szConfigsDir));
	formatex(szBadName_List, charsmax(szBadName_List), "/plugins/RE_Gag_System/RGS_Bad_Names.ini");
	add(szConfigsDir, charsmax(szConfigsDir), szBadName_List);
	iFile = fopen(szConfigsDir, "rt");

	if(!file_exists(szConfigsDir))
	{
		server_print("File not found, creating new one..");
		new iFile = fopen(szConfigsDir, "wt");
		
		if (iFile)
		{
			new szNewFile[512];
			formatex(szNewFile, charsmax(szNewFile), "// Add here your list of names which players cannot use\
				^n// Example:\
				^n^"Player^"\
				^n^"CS-WarZone Player^"\
				^n^"RGS Bad Name^"");
			fputs(iFile, szNewFile);
		}
		fclose(iFile);
		Load_BadName_List();
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

			ArrayPushString(Array:g_aList[BAD_NAMES], szName);

			iLine++;
		}
		fclose(iFile);
	}
	g_iTotalPhrases[BAD_NAMES] = iLine;
	server_print("[%s] Loaded %i bad names from file!", PLUGIN, g_iTotalPhrases[BAD_NAMES]);
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

	if (get_user_flags(id) & ADMIN_IMMUNITY && g_pCvarSetting[AUTOGAG_ADMIN_IMMUNITY])
		return PLUGIN_CONTINUE;

	if (g_pCvarSetting[AUTOGAG_BAD_NAMES])
	{
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
		if (g_iTotalPhrases[BAD_NAMES] > 0)
		{
			for (new i = 0; i < g_iTotalPhrases[BAD_NAMES]; i++)
			{
				ArrayGetString(Array:g_aList[BAD_NAMES], i, szExtraChecks, charsmax(szExtraChecks));
				if (containi(g_szName[id], szExtraChecks) != -1 || equali(g_szName[id], szExtraChecks))
				{
					server_cmd("kick #%d ^"[%s] Bad name [%s] detected! Changed it and connect again^"", get_user_userid(id), PLUGIN, szExtraChecks);
					return PLUGIN_HANDLED;
				}
			}
		}
		if (is_invalid(g_szName[id]))
		{
			server_cmd("kick #%d ^"[%s] IP/Site Pattern [%s] detected in name!^"", get_user_userid(id), PLUGIN, g_szName[id]);
			return PLUGIN_HANDLED;
		}
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
		server_print("   use time of 1914 for custom times, use time of 0 for permanent.");
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
	if (!is_user_connected(id) || get_user_flags(id) & ADMIN_IMMUNITY && g_pCvarSetting[AUTOGAG_ADMIN_IMMUNITY])
		return HC_CONTINUE;

	if (IsUserGagged(id, false) == GAG_YES)
	{
		SetHookChainReturn(ATYPE_BOOL, false);
		return HC_SUPERCEDE;
	}

	if (!equal(g_szName[id], szNewName))
	{
		copy(g_szName[id], charsmax(g_szName[]), szNewName);

		if (g_pCvarSetting[AUTOGAG_BAD_NAMES])
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

		if (g_iTotalPhrases[BAD_NAMES] > 0)
		{
			for (new i = 0; i < g_iTotalPhrases[BAD_NAMES]; i++)
			{
				ArrayGetString(Array:g_aList[BAD_NAMES], i, szExtraChecks, charsmax(szExtraChecks));
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

	GagUser(g_szName[id], g_szIP[id], g_pCvarSetting[AUTOGAG_TIME_BAD_NAMES], g_pCvarSetting[AUTOGAG_REASON_BAD_NAMES], fmt("[%s]", szReason), g_pCvarSetting[AUTOGAG_ADMIN_BAD_NAMES]);
	g_bBadNameDetected = false;
	g_bForced_Name_Change = false;
	return PLUGIN_HANDLED;
}

public RG__Entity_Think(iEnt)
{
	if (iEnt != g_iThinkingEnt || !g_pCvarSetting[PRINT_EXPIRED])
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

			if (g_pCvarSetting[HUD_SHOW] && g_bPlayerShuwHudMessage[id])
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

	if (IsUserGagged(id) == GAG_YES)
		return PLUGIN_HANDLED;

	if (get_user_flags(id) & ADMIN_IMMUNITY && g_pCvarSetting[AUTOGAG_ADMIN_IMMUNITY])
		return PLUGIN_CONTINUE;

	if (is_invalid(szMessage) && IsUserGagged(id, false) == GAG_NOT && g_pCvarSetting[AUTOGAG_ADVERTISE])
	{
		GagUser(g_szName[id], g_szIP[id], g_pCvarSetting[AUTOGAG_TIME_ADVERTISE], fmt("%s", g_pCvarSetting[AUTOGAG_REASON_ADVERTISE]), g_pCvarSetting[AUTOGAG_REASON_ADVERTISE], g_pCvarSetting[AUTOGAG_ADMIN_ADVERTISE]);
		return PLUGIN_HANDLED;
	}

	if (is_invalid(fmt("%n", id)) && IsUserGagged(id, false) == GAG_NOT && g_pCvarSetting[AUTOGAG_BAD_NAMES])
	{
		GagUser(fmt("%n", id), g_szIP[id], g_pCvarSetting[AUTOGAG_TIME_BAD_NAMES], g_pCvarSetting[AUTOGAG_REASON_BAD_NAMES], fmt("[%s]", g_szName[id]), g_pCvarSetting[AUTOGAG_ADMIN_BAD_NAMES]);
		server_cmd("kick #%d ^"[%s] IP/Site Pattern [%s] detected in name!^"", get_user_userid(id), PLUGIN, g_szName[id]);
		return PLUGIN_HANDLED;
	}
	
	if (g_iTotalPhrases[BLACK] > 0 && IsUserGagged(id, false) == GAG_NOT && g_pCvarSetting[AUTOGAG_BAD_WORDS])
	{
		for (new i = 0; i < g_iTotalPhrases[BLACK]; i++)
		{
			ArrayGetString(Array:g_aList[BLACK], i, szExtraChecks, charsmax(szExtraChecks));
			if (containi(szMessage, szExtraChecks) != -1 || equali(szMessage, szExtraChecks))
			{
				GagUser(g_szName[id], g_szIP[id], g_pCvarSetting[AUTOGAG_TIME_BAD_WORDS], g_pCvarSetting[AUTOGAG_REASON_BAD_WORDS], fmt("[%s]", szMessage), g_pCvarSetting[AUTOGAG_ADMIN_BAD_WORDS]);
				return PLUGIN_HANDLED;
			}
		}
	}

	if (is_user_spamming(id, szMessage) && IsUserGagged(id, false) == GAG_NOT && g_pCvarSetting[AUTOGAG_SPAM_CHAT])
	{
		return PLUGIN_CONTINUE;
	}

	return PLUGIN_CONTINUE;
}

bool:is_user_spamming(const id, const szSpamMessage[])
{
	new szExtraChecks[192];
	if (equal(g_szLastSaidSpam[id], szSpamMessage))
	{
		for (new i = 0; i < g_iTotalPhrases[WHITE]; i++)
		{
			ArrayGetString(Array:g_aList[WHITE], i, szExtraChecks, charsmax(szExtraChecks));
			if (equal(szSpamMessage, szExtraChecks))
			{
				g_iSpamCount[id] = 1;
				return false;
			}
		}
		if (++g_iSpamCount[id] >= g_pCvarSetting[AUTOGAG_SPAM_COUNT])
		{
			GagUser(g_szName[id], g_szIP[id], g_pCvarSetting[AUTOGAG_TIME_SPAM_CHAT], g_pCvarSetting[AUTOGAG_REASON_SPAM_CHAT], fmt("Spam: %s", g_szLastSaidSpam[id]), g_pCvarSetting[AUTOGAG_ADMIN_SPAM_CHAT]);
			return true;
		}
	}
	else
	{
		g_iSpamCount[id] = 1;
		copy(g_szLastSaidSpam[id], charsmax(g_szLastSaidSpam[]), szSpamMessage);
	}
	return false;
}

public Command_Gag(id, iLevel, iCmdId)
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

public Command_UnGag(id, iLevel, iCmdId)
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
					client_cmd(id, "messagemode REGS_TYPE_GAG_REASON");
					CC_SendMessage(id, "Type in the !treason!n, or !g!cancel !nto cancel.");
				}
				else if (g_iMenuSettings[id] == 1914)
				{
					client_cmd(id, "messagemode REGS_TYPE_GAG_TIME");
					CC_SendMessage(id, "Type in the !ttime in minutes!n, or !g!cancel !nto cancel.");
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
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, g_iMenuSettings[id] == 1914 ? "^n8. Gag time: \rCustom Time\w^n" : g_iMenuSettings[id] == 0 ? "^n8. Gag time: \rpermanently\w^n" : "^n8. Gag time: \y%i minutes\w^n", g_iMenuSettings[id]);
	
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

public Command_GagReason(id, level, cid)
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

	if (g_iMenuSettings[id] == 1914)
	{
		copy(g_szCustomTime_Reason, charsmax(g_szCustomTime_Reason), szReason);
		client_cmd(id, "messagemode REGS_TYPE_GAG_TIME");
		CC_SendMessage(id, "Type in the !ttime in minutes!n, or !g!cancel !nto cancel.");
	}
	else
	{
		GagUser(szName, szIP, g_iGagTime, szReason, "Gag by Menu", szAdminName);
		g_blIsUserMuted[g_iUserTarget[id]] = true;
	}
	return PLUGIN_HANDLED;
}

public Command_ReloadFile(id, level, cid)
{
	if (!cmd_access(id, level, cid, 2))
		return PLUGIN_HANDLED;

	new szFileName[MAX_NAME_LENGTH * 2];
	read_argv(1, szFileName, charsmax(szFileName));

	if (equali(szFileName, g_szFileNames[F_BLACKLIST]))
	{
		Load_BlackList();
		console_print(id, "You have succesfully reloaded file '%s.ini'!", g_szFileNames[F_BLACKLIST]);
	}
	else if (equali(szFileName, g_szFileNames[F_WHITELIST]))
	{
		Load_WhiteList();
		console_print(id, "You have succesfully reloaded file '%s.ini'!", g_szFileNames[F_WHITELIST]);
	}
	else if (equali(szFileName, g_szFileNames[F_BAD_NAMES]))
	{
		Load_BadName_List();
		console_print(id, "You have succesfully reloaded file '%s.ini'!", g_szFileNames[F_BAD_NAMES]);
	}
	else if (equali(szFileName, g_szFileNames[F_BAD_NAME_REPLACEMENTS]))
	{
		Load_BadName_ReplacementsList();
		console_print(id, "You have succesfully reloaded file '%s.ini'!", g_szFileNames[F_BAD_NAME_REPLACEMENTS]);
	}
	else if (equali(szFileName, g_szFileNames[F_SETTINGS]))
	{
		server_cmd("exec addons/amxmodx/configs/plugins/RE_Gag_System/%s.cfg", g_szFileNames[F_SETTINGS]);
		console_print(id, "You have succesfully reloaded file '%s.cfg'!", g_szFileNames[F_SETTINGS]);
	}

	return PLUGIN_HANDLED;
}

public Command_GagTime(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1) || !is_user_connected(g_iUserTarget[id]))
		return PLUGIN_HANDLED;
	
	new szTime[MAX_REASON_LENGHT], szName[MAX_NAME_LENGTH], szIP[MAX_IP_LENGTH], szAdminName[MAX_NAME_LENGTH];
	read_argv(1, szTime, charsmax(szTime));
	
	if (equali(szTime, "!cancel"))
	{
		g_szCustomTime_Reason[0] = EOS;
		displayGagMenu(id, g_iMenuPosition[id]);
		return PLUGIN_HANDLED;
	}

	new iGagTime = str_to_num(szTime);

	if (~get_user_flags(id) & (ADMIN_KICK | ADMIN_RCON) && iGagTime <= 0)
	{
		client_print(id, print_center, "You have no access to that command!");
		displayGagMenu(id, g_iMenuPosition[id]);
		return PLUGIN_HANDLED;
	}


	get_user_name(id, szAdminName, charsmax(szAdminName));
	get_user_name(g_iUserTarget[id], szName, charsmax(szName));
	get_user_ip(g_iUserTarget[id], szIP, charsmax(szIP), 1);


	if (equal(g_iMenuSettingsReason[id], "Custom Reason") || g_iMenuSettingsReason[id][0] == EOS)
		GagUser(szName, szIP, iGagTime, g_szCustomTime_Reason, "Gag by Menu", szAdminName);
	else
		GagUser(szName, szIP, iGagTime, g_iMenuSettingsReason[id], "Gag by Menu", szAdminName);

	g_blIsUserMuted[g_iUserTarget[id]] = true;
	g_szCustomTime_Reason[0] = EOS;
	return PLUGIN_HANDLED;
}

public Command_GagMenu(id, level, cid)
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
		copy(g_iMenuSettingsReason[id], charsmax(g_iMenuSettingsReason[]), "Custom Gag Reason");
	}
	displayGagMenu(id, g_iMenuPosition[id] = 0);

	return PLUGIN_HANDLED;
}

public Command_CleanDB(id, iLevel, iCmdId)
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
	new szHudMessage[MAX_FMT_LENGTH];

	if (!nvault_get(g_iNVaultHandle, szIP, szTemp, charsmax(szTemp)))
	{
		formatex(szResult, charsmax(szResult), "User with IP %s not found.", szIP);
		return szResult;
	}

	#if defined CURL_MODULE
	copy(g_szDiscordReplacements[GAG_REASON], charsmax(g_szDiscordReplacements[GAG_REASON]), GetGaggedPlayerInfo_Reason_Discord(szIP));
	#endif


	nvault_remove(g_iNVaultHandle, szIP);

	if (!equal(szName, szIP))
	{
		new iTarget = cmd_target(0, szName, 0);

		g_blIsUserMuted[iTarget] = false;

		CC_SendMessage(iTarget, "You have been ungagged by admin !t%s!n!", szAdmin);

		CC_SendMessage(0, "Player !t%s !nhas been ungagged by !g%s!n.", szName, szAdmin);

		formatex(szHudMessage, charsmax(szHudMessage), "%s has been ungagged by %s", szName, szAdmin);
	}

	new id = find_player_ex(FindPlayer_MatchIP, szIP);
	if (id != 0)
	{
		g_iSpamCount[id] = 0;
		ExecuteForward(g_UngagForward, g_iUnused, id);
	}

	new iPlayers[MAX_PLAYERS], iNum, iPlayer;
	get_players(iPlayers, iNum);
	
	for (--iNum; iNum >= 0; iNum--)
	{
		iPlayer = iPlayers[iNum];
		
		if (g_pCvarSetting[HUD_SHOW] && g_bPlayerShuwHudMessage[id])
		{
			rg_send_hudmessage(iPlayer, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0);
		}
	}

	#if defined LOG_GAGS
	log_to_file(g_szLogFile, "[UNGAG] ADMIN: %s | TARGET_NAME: %s [IP: %s]", szAdmin, szName, szIP);
	#endif

	new iAdmin_Id = get_user_index(szAdmin);
	copy(g_szDiscordReplacements[ADMIN_NAME], charsmax(g_szDiscordReplacements[ADMIN_NAME]), szAdmin);
	copy(g_szDiscordReplacements[PLAYER_NAME], charsmax(g_szDiscordReplacements[PLAYER_NAME]), szName);

	new szAuthID[2][MAX_AUTHID_LENGTH];
	get_user_authid(iAdmin_Id, szAuthID[0], charsmax(szAuthID[]));
	get_user_authid(id, szAuthID[1], charsmax(szAuthID[]));

	copy(g_szDiscordReplacements[ADMIN_ID], charsmax(g_szDiscordReplacements[ADMIN_ID]), szAuthID[0]);
	copy(g_szDiscordReplacements[PLAYER_ID], charsmax(g_szDiscordReplacements[PLAYER_ID]), szAuthID[1]);

	copy(g_szDiscordReplacements[PLAYER_IP], charsmax(g_szDiscordReplacements[PLAYER_IP]), szIP);

	copy(g_szDiscordReplacements[GAG_ACTION], charsmax(g_szDiscordReplacements[GAG_ACTION]), "PLAYER UNGAG");
	#if defined GRIP_MODULE
	copy(g_szDiscordReplacements[GAG_REASON], charsmax(g_szDiscordReplacements[GAG_REASON]), "UNGAG BY ADMIN");
	#endif

	copy(g_szDiscordReplacements[GAG_TIME], charsmax(g_szDiscordReplacements[GAG_TIME]), "N/A");

	#if defined GRIP_MODULE
	send_report(id);
	#endif

	#if defined CURL_MODULE
	send_discord_message(id, false);
	#endif

	copy(szResult, charsmax(szResult), "Player has been ungagged");
	return szResult;
}

GagUser(szName[], szIP[], iDuration, szReason[], szReasonAdminOnly[], szAdminName[])
{
	new iExpireTime = iDuration != 0 ? get_systime() + (iDuration * 60) : 0;
	new szHudMessage[MAX_FMT_LENGTH];

	new szResult[64];

	if (nvault_get(g_iNVaultHandle, szIP, szResult, charsmax(szResult)))
	{
		copy(szResult, charsmax(szResult), "Player is already gagged.");
		return szResult;
	}

	new id = find_player_ex(FindPlayer_MatchIP, szIP);

	if (id != 0)
	{
		ExecuteForward(g_GagForward, g_iUnused, id);
	}

	new szValue[512];
	formatex(szValue, charsmax(szValue), "^"%s^"#^"%s^"#^"%s^"#%d#^"%s^"", szName, szReason, szReasonAdminOnly, iExpireTime, szAdminName);

	if (iExpireTime == 0)
	{
		CC_SendMessage(0, "Player!t %s!n has been gagged by!g %s!n. Reason: !t%s!n. Gag expires!t never!n.", szName, szAdminName, szReason);
		formatex(szHudMessage, charsmax(szHudMessage), "%s has been gagged by %s^nExpires: Never^nReason: %s", szName, szAdminName, szReason);
	}
	else
	{
		CC_SendMessage(0, "Player!t %s!n has been gagged by!g %s!n. Reason: !t%s!n. Gag expires!t %s", szName, szAdminName, szReason, GetTimeAsString(iDuration * 60));
		formatex(szHudMessage, charsmax(szHudMessage), "%s has been gagged by %s^nExpires in %s^nReason: %s", szName, szAdminName, GetTimeAsString(iDuration * 60), szReason);
	}

	new iPlayers[MAX_PLAYERS], iNum, iPlayer;
	get_players(iPlayers, iNum);
	
	for (--iNum; iNum >= 0; iNum--)
	{
		iPlayer = iPlayers[iNum];

		if (g_pCvarSetting[HUD_SHOW] && g_bPlayerShuwHudMessage[iPlayer])
		{
			rg_send_hudmessage(iPlayer, szHudMessage, 0.05, 0.30, random(256), random_num(100, 255), random(256), 150, 5.0, 0.10, 0.20, -1, 2, random_num(0, 100), random_num(0, 100), random_num(0, 100), 200, 2.0);
		}
		
	}
	
	emit_sound(0, CHAN_AUTO, g_szGagSound, 1.0, ATTN_NORM, SND_SPAWNING, PITCH_NORM);
	

	#if defined LOG_GAGS
	log_to_file(g_szLogFile, "ADMIN: %s | PLAYER: %s [IP: %s] | REASON: %s | TIME: %s", szAdminName, szName, szIP, szReason, GetTimeAsString(iDuration * 60));
	#endif

	new iAdmin_Id = get_user_index(szAdminName);
	copy(g_szDiscordReplacements[ADMIN_NAME], charsmax(g_szDiscordReplacements[ADMIN_NAME]), szAdminName);
	copy(g_szDiscordReplacements[PLAYER_NAME], charsmax(g_szDiscordReplacements[PLAYER_NAME]), szName);

	new szAuthID[2][MAX_AUTHID_LENGTH];
	get_user_authid(iAdmin_Id, szAuthID[0], charsmax(szAuthID[]));
	get_user_authid(id, szAuthID[1], charsmax(szAuthID[]));

	copy(g_szDiscordReplacements[ADMIN_ID], charsmax(g_szDiscordReplacements[ADMIN_ID]), szAuthID[0]);
	copy(g_szDiscordReplacements[PLAYER_ID], charsmax(g_szDiscordReplacements[PLAYER_ID]), szAuthID[1]);

	copy(g_szDiscordReplacements[PLAYER_IP], charsmax(g_szDiscordReplacements[PLAYER_IP]), szIP);

	copy(g_szDiscordReplacements[GAG_ACTION], charsmax(g_szDiscordReplacements[GAG_ACTION]), "PLAYER GAG");
	copy(g_szDiscordReplacements[GAG_REASON], charsmax(g_szDiscordReplacements[GAG_REASON]), szReason);
	copy(g_szDiscordReplacements[GAG_TIME], charsmax(g_szDiscordReplacements[GAG_TIME]), GetTimeAsString(iDuration * 60));
	
	nvault_set(g_iNVaultHandle, szIP, szValue);

	#if defined GRIP_MODULE
	send_report(id);
	#endif

	#if defined CURL_MODULE
	send_discord_message(id, true);
	#endif
	
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
#if defined CURL_MODULE
stock GetGaggedPlayerInfo_Reason_Discord(const iPlayerIP[])
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
		
		formatex(szReasonFmt, charsmax(szReasonFmt), "%s", szReason, szReasonAdminOnly);
	}
	return szReasonFmt;
}
#endif
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
#if defined GRIP_MODULE
public send_report(id)
{
	new text[1024];
	format(text, charsmax(text), "content=%s", DISCORD_REPORT_GRIP);

	replace_string(text, charsmax(text), "{target}", g_szDiscordReplacements[PLAYER_NAME]);
	replace_string(text, charsmax(text), "{time}", g_szDiscordReplacements[GAG_TIME]);
	replace_string(text, charsmax(text), "{reason}", g_szDiscordReplacements[GAG_REASON]);
	replace_string(text, charsmax(text), "{admin}", g_szDiscordReplacements[ADMIN_NAME]);
	replace_string(text, charsmax(text), "{actiontype}", g_szDiscordReplacements[GAG_ACTION]);
	replace_string(text, charsmax(text), "{adminid}", g_szDiscordReplacements[ADMIN_ID]);
	replace_string(text, charsmax(text), "{targetid}", g_szDiscordReplacements[PLAYER_ID]);
	replace_string(text, charsmax(text), "{targetip}", g_szDiscordReplacements[PLAYER_IP]);

	GoRequest(id, DISCORD_WEBHOOK, "Handler_SendReason", GripRequestTypePost, text);
}

public Handler_SendReason(const id)
{
	if(!is_user_connected(id))
		return;

	if(!HandlerGetErr())
		return;
}

public GoRequest(const id, const site[], const handler[], const GripRequestType:type, data[])
{
	new GripRequestOptions:options = grip_create_default_options();
	grip_options_add_header(options, "Content-Type", "application/x-www-form-urlencoded");

	new GripBody: body = grip_body_from_string(data);
	grip_request(site, body, type, handler, options, id);

	grip_destroy_body(body);
	grip_destroy_options(options);
}

public bool:HandlerGetErr()
{
	if(grip_get_response_state() == GripResponseStateError)
	{
		log_amx("ResponseState is Error");
		return false;
	}

	new GripHTTPStatus:err;
	if((err = grip_get_response_status_code()) != GripHTTPStatusNoContent)
	{
		log_amx("ResponseStatusCode is %d", err);
		return false;
	}
	
	return true;
}
#endif

#if defined CURL_MODULE
enum dataStruct { curl_slist: linkedList };

public send_discord_message(id, bool:gag)
{
	new CURL: pCurl, curl_slist: pHeaders;
	new sData[dataStruct];
	pHeaders = curl_slist_append(pHeaders, "Content-Type: application/json");
	pHeaders = curl_slist_append(pHeaders, "User-Agent: pay-attention");
	pHeaders = curl_slist_append(pHeaders, "Connection: Keep-Alive");
    
	sData[linkedList] = pHeaders;

	if ((pCurl = curl_easy_init())) {
		new text[CURL_BUFFER_SIZE];

		if (gag)
		{
			formatex(text, charsmax(text), 
					"{ ^"content^": ^"{mention_role}^", \
						^"embeds^": \
							[ {  ^"author^": { ^"name^": ^"{server_name}^",  ^"url^": ^"{server_url}^" }, \
					            ^"color^": %d, ^"title^": ^"{server_ip}^", \
					            ^"footer^": {  ^"text^": ^"RE: Gag System Reports^",  ^"icon_url^": ^"https://avatars.githubusercontent.com/u/83426246?v=4^" }, \
					            ^"thumbnail^": { ^"url^": ^"{thumbnail}^" }, \
					            ^"image^": { ^"url^": ^"{banner}^" }, \
					            ^"fields^": [ \
					            	{ ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					            	{ ^"name^": ^"ADMIN INFO^", ^"value^": ^"Name: {admin} \nSteamID: {adminid}\n[Check Admin Steam](https://www.steamidfinder.com/lookup/{adminid}/)^", ^"inline^": false }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					                { ^"name^": ^"PLAYER INFO^", ^"value^": ^"Name: {target} \nSteamID: {targetid} \nIP: {targetip}\n[Check Player Steam](https://www.steamidfinder.com/lookup/{targetid}/)^", ^"inline^": false }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" },\
					                { ^"name^": ^"Time^", ^"value^": ^"{time}^", ^"inline^": false }, \
					                { ^"name^": ^"Reason^", ^"value^": ^"{reason}^", ^"inline^": false }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					                { ^"name^": ^"ACTION TYPE:^", ^"value^": ^"{actiontype}^", ^"inline^": false } \
					            	] \
					        	} \
					    	] \
					}", random(19141997));
		}
		else
		{
			formatex(text, charsmax(text), 
					"{ ^"content^": ^"{mention_role}^", \
						^"embeds^": \
							[ {  ^"author^": { ^"name^": ^"{server_name}^",  ^"url^": ^"{server_url}^" }, \
					            ^"color^": %d, ^"title^": ^"{server_ip}^", \
					            ^"footer^": {  ^"text^": ^"RE: Gag System Reports^",  ^"icon_url^": ^"https://avatars.githubusercontent.com/u/83426246?v=4^" }, \
					            ^"thumbnail^": { ^"url^": ^"{thumbnail}^" }, \
					            ^"image^": { ^"url^": ^"{banner}^" }, \
					            ^"fields^": [ \
					           	 	{ ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					            	{ ^"name^": ^"ADMIN INFO^", ^"value^": ^"Name: {admin} \nSteamID: {adminid}\n[Check Admin Steam](https://www.steamidfinder.com/lookup/{adminid}/)^", ^"inline^": false }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					                { ^"name^": ^"PLAYER INFO^", ^"value^": ^"Name: {target} \nSteamID: {targetid} \nIP: {targetip} \n[Check Player Steam](https://www.steamidfinder.com/lookup/{targetid}/)^", ^"inline^": false }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					                { ^"name^": ^"Reason for the gag^", ^"value^": ^"{reason}^", ^"inline^": false }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					                { ^"name^": ^"ACTION TYPE:^", ^"value^": ^"{actiontype}^", ^"inline^": false } \
					            	] \
					        	} \
					    	] \
					}", random(19141997));
		}

		replace_string(text, charsmax(text), "{mention_role}", MENTION_ROLE);
		replace_string(text, charsmax(text), "{server_name}", SERVER_NAME);
		replace_string(text, charsmax(text), "{server_url}", SERVER_URL);
		replace_string(text, charsmax(text), "{server_ip}", SERVER_IP);
		replace_string(text, charsmax(text), "{thumbnail}", THUMBNAIL);
		replace_string(text, charsmax(text), "{banner}", BANNER);

		replace_string(text, charsmax(text), "{target}", g_szDiscordReplacements[PLAYER_NAME]);
		replace_string(text, charsmax(text), "{time}", g_szDiscordReplacements[GAG_TIME]);
		replace_string(text, charsmax(text), "{reason}", g_szDiscordReplacements[GAG_REASON]);
		replace_string(text, charsmax(text), "{admin}", g_szDiscordReplacements[ADMIN_NAME]);
		replace_string(text, charsmax(text), "{actiontype}", g_szDiscordReplacements[GAG_ACTION]);
		replace_string(text, charsmax(text), "{adminid}", g_szDiscordReplacements[ADMIN_ID]);
		replace_string(text, charsmax(text), "{targetid}", g_szDiscordReplacements[PLAYER_ID]);
		replace_string(text, charsmax(text), "{targetip}", g_szDiscordReplacements[PLAYER_IP]);

		curl_easy_setopt(pCurl, CURLOPT_URL, DISCORD_WEBHOOK);
		curl_easy_setopt(pCurl, CURLOPT_COPYPOSTFIELDS, text);
		curl_easy_setopt(pCurl, CURLOPT_CUSTOMREQUEST, "POST");
		curl_easy_setopt(pCurl, CURLOPT_HTTPHEADER, pHeaders);
		curl_easy_setopt(pCurl, CURLOPT_SSL_VERIFYPEER, 0); 
		curl_easy_setopt(pCurl, CURLOPT_SSL_VERIFYHOST, 0); 
		curl_easy_setopt(pCurl, CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1); 
		curl_easy_setopt(pCurl, CURLOPT_FAILONERROR, 0); 
		curl_easy_setopt(pCurl, CURLOPT_FOLLOWLOCATION, 0); 
		curl_easy_setopt(pCurl, CURLOPT_FORBID_REUSE, 0); 
		curl_easy_setopt(pCurl, CURLOPT_FRESH_CONNECT, 0); 
		curl_easy_setopt(pCurl, CURLOPT_CONNECTTIMEOUT, 10); 
		curl_easy_setopt(pCurl, CURLOPT_TIMEOUT, 10);
		curl_easy_setopt(pCurl, CURLOPT_POST, 1);
		curl_easy_setopt(pCurl, CURLOPT_WRITEFUNCTION, "@Response_Write");
		curl_easy_perform(pCurl, "@Request_Complete", sData, dataStruct);
    }
}

@Response_Write(const data[], const size, const nmemb)
{
	server_print("Response body: \n%s", data);
	return size * nmemb;
}

@Request_Complete(CURL: curl, CURLcode: code, const data[dataStruct])
{
	curl_easy_cleanup(curl);
	curl_slist_free_all(data[linkedList]);
}
#endif