/**
 * vim: set ts=4 :
 * =============================================================================
 * sm_twitch_recognition
 * Idea is to scan a player's steam profile for a url to twitch.tv.  It would
 * be assumed that they put their own url on their profile.  Then that twitch
 * channel is queried to check if it is currently streaming. If it is then
 * that player is streaming live on the server right now.
 *
 * Copyright 2014 CrimsonTautology
 * =============================================================================
 *
 */

#pragma semicolon 1

#include <sourcemod>
#include <twitch_recognition>
#include <regex>
#include <steamtools>
#include <smjansson>

#define PLUGIN_VERSION "0.1"

public Plugin:myinfo =
{
    name = "Twitch Recognition",
    author = "CrimsonTautology",
    description = "Recognize which players on the server are livestreaming to twitch.tv",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm_twitch_recognition"
};

#define MAX_COMMUNITYID_LENGTH 18 

new bool:g_DoTwitchCheck[MAXPLAYERS+1] = {false, ...};
new bool:g_HasTwitchChannel[MAXPLAYERS+1] = {false, ...};
new bool:g_IsStreaming[MAXPLAYERS+1] = {false, ...};

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

    HookEvent("player_spawn", Event_PlayerSpawn);

    RegConsoleCmd("sm_test", Command_Test, "TODO: TEST");
}

public OnClientConnected(client)
{
    g_DoTwitchCheck[client] = true;
    g_HasTwitchChannel[client] = false;
    g_IsStreaming[client] = false;
}

public OnClientDisconnect(client)
{
    g_DoTwitchCheck[client] = false;
    g_HasTwitchChannel[client] = false;
    g_IsStreaming[client] = false;
}

public Action:Command_Test(client, args)
{
    return Plugin_Handled;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    PrintToChatAll("player spawn %d", client); //TODO
    //if(g_DoTwitchCheck[client])
    {
        QuerySteamWorksApi(client);
        //QueryTwitchApi(client, "360Chrism");
        g_DoTwitchCheck[client] = false;
    }
}


QuerySteamWorksApi(client)
{
    if (!IsEnabled()) return;

    PrintToChatAll("QuerySteamWorksApi: %d", client); //TODO

    //Build steamworks url
    decl String:url[256], String:uid[MAX_COMMUNITYID_LENGTH];
    Steam_GetCSteamIDForClient(client, uid, sizeof(uid));
    Format(url, sizeof(url),
            "%s%s/%s", STEAM_WORKS_ROUTE, uid, STEAM_WORKS_XML_PARAM);

    PrintToChatAll("%s", url);//TODO
    new HTTPRequestHandle:request = Steam_CreateHTTPRequest(HTTPMethod_GET, url);

    if(request == INVALID_HTTP_HANDLE)
    {
        return;
    }
    //Steam_SetHTTPRequestGetOrPostParameter(request, "l", "english"); //Steamworks does not send content-length unless there is a parameter?
    Steam_SetHTTPRequestHeaderValue(request, "Content-Length", "0");

    new player = client > 0 ? GetClientUserId(client) : 0;
    Steam_SendHTTPRequest(request, ReceiveSteamWorksApi, player);
}

public ReceiveSteamWorksApi(HTTPRequestHandle:request, bool:successful, HTTPStatusCode:code, any:userid)
{
    new client = GetClientOfUserId(userid);
    if(!successful || code != HTTPStatusCode_OK)
    {
        LogError("[Twitch] Error at RecieveSteamWorksApi (HTTP Code %d; success %d)", code, successful);
        Steam_ReleaseHTTPRequest(request);
        return;
    }

    new  body_size = Steam_GetHTTPResponseBodySize(request); 
    PrintToChatAll("BodySize: %d", body_size);//TODO
    decl String:data[body_size], String:channel[256];

    Steam_GetHTTPResponseBodyData(request, data, body_size);
    Steam_ReleaseHTTPRequest(request);

    //NOTE : This is very sloppy; the text returned could well beover 20kb;
    //most of the group and owned game stuff is useless or could contain
    //false-positive twitch urls.  However the more useful SteamApi does not
    //query a steam profile's summary, headline or links fields.

    //Search user's steamworks data for twitch.tv urls.
    //We're assuming they would only put their own url on their page
    new Handle:channel_regex = CompileRegex("twitch.tv/(\\w+)");
    MatchRegex(channel_regex, data);

    if(GetRegexSubString(channel_regex, 1, channel, sizeof(channel)))
    {
        PrintToChatAll("%d is a twitch user", client); //TODO
        //A twitch url was found; assume it is the player's
        g_HasTwitchChannel[client] = true;
        QueryTwitchApi(client, channel);
    }else{
        PrintToChatAll("%d is not a twitch user", client); //TODO
    }
}

QueryTwitchApi(client, String:channel[])
{
    if (!IsEnabled()) return;

    PrintToChatAll("QueryTwitchApi: %d - %s", client, channel); //TODO
    //Build twitch url
    decl String:url[256];
    Format(url, sizeof(url),
            "%s%s", TWITCH_ROUTE, channel);

    PrintToChatAll("%s", url);//TODO
    new HTTPRequestHandle:request = Steam_CreateHTTPRequest(HTTPMethod_GET, url);

    if(request == INVALID_HTTP_HANDLE)
    {
        return;
    }

    new player = GetClientUserId(client);
    Steam_SendHTTPRequest(request, ReceiveTwitchApi, player);
}

public ReceiveTwitchApi(HTTPRequestHandle:request, bool:successful, HTTPStatusCode:code, any:userid)
{
    new client = GetClientOfUserId(userid);

    if(!successful || code != HTTPStatusCode_OK)
    {
        LogError("[Twitch] Error at RecieveTwitchApi (HTTP Code %d; success %d)", code, successful);
        Steam_ReleaseHTTPRequest(request);
        return;
    }

    new  body_size = Steam_GetHTTPResponseBodySize(request); 
    PrintToChatAll("BodySize: %d", body_size);//TODO
    decl String:data[body_size];

    Steam_GetHTTPResponseBodyData(request, data, body_size);

    //parse JSON response
    new Handle:json = json_load(data);
    new Handle:stream = json_object_get(json, "stream");

    if(stream == INVALID_HANDLE)
    {
        //json is wrong
        PrintToChatAll("%d ruh-roh", client); //TODO
    }else if(json_is_null(stream))
    {
        //Stream object is null, thus player is not streaming
        g_IsStreaming[client] = false;
        PrintToChatAll("%d is not streaming", client); //TODO
    }else{
        //Player is streaming
        g_IsStreaming[client] = true;

        //Get more data
        new String:display_name[128], String:status[128], String:url[128];
        new viewers = json_object_get_int(stream, "viewers");

        new Handle:channel = json_object_get(stream, "channel");
        json_object_get_string(channel, "display_name", display_name, sizeof(display_name));
        json_object_get_string(channel, "status", status, sizeof(status));
        json_object_get_string(channel, "url", url, sizeof(url));
        CloseHandle(channel);

        //Do whatever
        PrintToChatAll("%d people are watching %s stream \"%s\"", viewers, display_name, status);//TODO
        PrintToChatAll("visit %s", url);//TODO

    }
    CloseHandle(stream);
    CloseHandle(json);
}

bool:IsEnabled()
{
    return GetConVarBool(g_Cvar_Enabled);
}
