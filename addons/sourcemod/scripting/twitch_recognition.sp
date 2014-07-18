/**
 * vim: set ts=4 :
 * =============================================================================
 * _plugin_name_
 * TODO: Describe this plugin
 *
 * Copyright _the_year_ _your_name_
 * =============================================================================
 *
 */

#pragma semicolon 1

#include <sourcemod>
#include <twitch_recognition>
#include <regex>
#include <steamtools>

#define PLUGIN_VERSION "0.1"

public Plugin:myinfo =
{
    name = "_plugin_name_",
    author = "_your_name_",
    description = "TODO: description",
    version = PLUGIN_VERSION,
    url = "https://github.com/_your_name_/_plugin_name_"
};


new Handle:g_Cvar_Enabled = INVALID_HANDLE;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    if (LibraryExists("twitch_recognition"))
    {
        strcopy(error, err_max, "twitch_recognition already loaded, aborting.");
        return APLRes_Failure;
    }

    RegPluginLibrary("twitch_recognition"); 

    return APLRes_Success;
}

public OnPluginStart()
{
    LoadTranslations("twitch_recognition.phrases");

    g_Cvar_Enabled = CreateConVar("sm__plugin_name__enabled", "1", "Enabled");

    RegConsoleCmd("sm_test", Command_Test, "TODO: TEST");
}

public Action:Command_Test(client, args)
{
    return Plugin_Handled;
}

QuerySteamWorksApi(client)
{
    if (!IsEnabled()) return;

    //Build steamworks url
    decl String:url[256], String:uid[MAX_COMMUNITYID_LENGTH];
    Steam_GetCSteamIDForClient(client, uid, sizeof(uid));
    Format(url, sizeof(url),
            "%s%s", STEAM_WORKS_ROUTE, uid);

    new HTTPRequestHandle:request = CreateIGARequest(url);

    if(request == INVALID_HTTP_HANDLE)
    {
        return;
    }

    Steam_SetHTTPRequestGetOrPostParameter(request, "xml", "1");

    new player = client > 0 ? GetClientUserId(client) : 0;
    Steam_SendHTTPRequest(request, ReceiveSteamWorksApi, player);
}

ReceiveSteamWorksApi(HTTPRequestHandle:request, bool:successful, HTTPStatusCode:code, any:userid)
{
    new client = GetClientOfUserId(userid);
    if(!successful || code != HTTPStatusCode_OK)
    {
        LogError("[Twitch] Error at RecieveSteamWorksApi (HTTP Code %d; success %d)", code, successful);
        Steam_ReleaseHTTPRequest(request);
        return;
    }

    decl String:data[4096], String:channel[256];
    Steam_GetHTTPResponseBodyData(request, data, sizeof(data));
    Steam_ReleaseHTTPRequest(request);

    //Search user's steamworks data for twitch.tv urls.  We're assuming they but their own url on their page
    new channel_regex = CompileRegex("twitch.tv/(\\w+)");
    MatchRegex(channel_regex, data);
    
    if(GetRegexSubstring(channel_regex, 1, channel, sizeof(channel)))
    {
        QueryTwitchApi(client, channel);
    }
}

QueryTwitchApi(client, String:channel[])
{
    if (!IsEnabled()) return;

    //Build twitch url
    decl String:url[256];
    Format(url, sizeof(url),
            "%s%s", TWITCH_ROUTE, channel);

    new HTTPRequestHandle:request = CreateIGARequest(url);

    if(request == INVALID_HTTP_HANDLE)
    {
        return;
    }

    new player = client > 0 ? GetClientUserId(client) : 0;
    Steam_SendHTTPRequest(request, ReceiveTwitchApi, player);
}

ReceiveTwitchApi(HTTPRequestHandle:request, bool:successful, HTTPStatusCode:code, any:userid)
{
}

bool:IsEnabled()
{
    return GetConVarBool(g_Cvar_Enabled);
}
