#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <shavit>
#include <multicolors>
#include <as_dr_queue>

#pragma semicolon 1
#pragma newdecls required

#define REFRESH_HUD_INTERVAL    1.5
#define TEXT_PREFIX             "{lightred}" ... "[Deathrun kolejka]" ... "\x01"

Handle g_hudTextHandle,
    g_hudRefreshTimer;

ArrayList g_listQueue;

public Plugin myinfo = {
    name = "Deathrun Queue",
    description = "Queue to TT for Deathrun",
    author = "Avgariat",
    version = "2.0",
    url = "https://arenaskilla.pl"
};

public void OnPluginStart() {
    RegConsoleCmd("pozycja", cmd_showPosition);

    HookEvent("round_start", event_roundStart);
    HookEvent("round_end", event_roundEnd);
    HookEvent("player_death", event_onPlayerDeath);
    HookEvent("player_spawn", event_onPlayerSpawn);
    
    g_listQueue = new ArrayList();
    g_hudTextHandle = CreateHudSynchronizer();
    g_hudRefreshTimer = CreateTimer(REFRESH_HUD_INTERVAL, timer_refreshHudText, _, TIMER_REPEAT);
    for (int i = 1; i < MaxClients; i++) if (isValidPlayer(i)) {
        OnClientPutInServer(i);
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    CreateNative("dr_getPosInQueue", native_getClientsPosition);
    CreateNative("dr_getClientByPosInQueue", native_getClientByPosistion);
}

public void OnClientPutInServer(int client) {
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    if (g_hudRefreshTimer == null) {
        g_hudRefreshTimer = CreateTimer(REFRESH_HUD_INTERVAL, timer_refreshHudText, _, TIMER_REPEAT);
    }
}

public void OnClientDisconnect(int client) {
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
    q_remove(client);
}

public Action cmd_showPosition(int client, int args) {
    if (!IsPlayerAlive(client)) {
        CPrintToChat(client, "%s Nie możesz użyć komendy, ponieważ nie żyjesz.", TEXT_PREFIX);
    }
    else if (GetClientTeam(client) != CS_TEAM_CT) {
        CPrintToChat(client, "%s Nie możesz sprawdzić pozycji, ponieważ jesteś w Terrorystach.", TEXT_PREFIX);
    }
    else if (!q_isInQueue(client)) {
        CPrintToChat(client, "%s Jeszcze nie przeszedłeś mapy.", TEXT_PREFIX);
    }
    else {
        CPrintToChat(client, "%s Twoja pozycja w kolejce: \x06%d", TEXT_PREFIX, q_getClientsPos(client));
    }

    return Plugin_Handled;
}

public Action event_roundStart(Event event, const char[] name, bool dontBroadcast) {
    q_clear();
}

public Action event_roundEnd(Event event, const char[] name, bool dontBroadcast) {
    q_clear();
}

public Action event_onPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    setClientColorNone(client);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
    if (!isValidPlayer(attacker, true) || !isValidPlayer(victim, true)) return Plugin_Continue;
    
    int teamAttacker, teamVictim;
    teamAttacker = GetClientTeam(attacker);
    teamVictim = GetClientTeam(victim);
    // if ct, tt or tt, ct
    if (teamAttacker + teamVictim == CS_TEAM_CT + CS_TEAM_T) {
        // ct, tt
        if (teamAttacker == CS_TEAM_CT && attacker == q_getFirstClient()) return Plugin_Continue;
        // tt, ct
        if (teamAttacker == CS_TEAM_T && victim == q_getFirstClient()) return Plugin_Continue;
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public void Shavit_OnFinish(int client) {
    if (!isValidPlayer(client, true) || q_isInQueue(client)) return;
    
    if (GetClientTeam(client) == CS_TEAM_CT) {
        q_enqueue(client);

        if (client == q_getFirstClient()) {
            setClientColorCT(client);
            CPrintToChat(client, "%s Przeszedłeś mapę, walczysz przeciwko Terroryscie!", TEXT_PREFIX);
        }
        else {
            CPrintToChat(client, "%s Jesteś \x06%d \x01w kolejce.", TEXT_PREFIX, q_getClientsPos(client));
        }
    }
}

public Action event_onPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    q_remove(client);
}

public Action timer_refreshHudText(Handle timer) {
    char buffer[512] = "Kolejka:";
    for (int i = 0, client; i < 5; i++) {
        client = q_getClientByPos(i);
        if (isValidPlayer(client)) {
            Format(buffer, sizeof(buffer), "%s\n%d. %N", buffer, i+1, client);
        }
    }

    int count = 0;
    for (int i = 1; i <= MaxClients; i++) if (isValidPlayer(i)) {
        ClearSyncHud(i, g_hudTextHandle);
        SetHudTextParams(0.03, 0.12, 10.0, 0, 210, 0, 255, 0, 40.0, 0.0, 0.0);
        ShowSyncHudText(i, g_hudTextHandle, buffer);
        count++;
    }

    if (!count) {
        g_hudRefreshTimer = null;
        return Plugin_Stop;
    }
    return Plugin_Continue;
}

public int native_getClientsPosition(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    return q_getClientsPos(client);
}

public int native_getClientByPosistion(Handle plugin, int numParams) {
    int pos = GetNativeCell(1) + 1;
    return q_getClientByPos(pos);
}

bool isValidPlayer(int client, bool isAlive = false) {
    if(client < 1 || client > MaxClients)
        return false;
    if(!IsClientInGame(client) || IsFakeClient(client))
        return false;
    if(isAlive && !IsPlayerAlive(client))
        return false;
    return true;
}

void setClientColorCT(int client) {
    SetEntityRenderColor(client, 0, 255, 0, 255);
}

void setClientColorNone(int client) {
    SetEntityRenderColor(client, 255, 255, 255, 255);
}

bool q_isInQueue(int client) {
    return g_listQueue.FindValue(client) != -1;
}

int q_getFirstClient() {
    return q_getClientByPos(0);
}

void q_remove(int client) {
    if (!q_isInQueue(client)) return;
    
    int clientPos = g_listQueue.FindValue(client);
    if (clientPos == -1) return;
    g_listQueue.Erase(clientPos);
    if (clientPos == 0 && g_listQueue.Length > 0) {
        int nextFirst = g_listQueue.Get(0);
        setClientColorCT(nextFirst);
        CPrintToChat(nextFirst, "%s Teraz twoja kolej, walczysz przeciwko Terroryscie!", TEXT_PREFIX);
    }
    for (int i = clientPos; i < g_listQueue.Length; i++) if (isValidPlayer(i)) {
        CPrintToChat(i, "%s Twoja kolejka zmniejszyła się o\x06 1 miejsce\x01!", TEXT_PREFIX);
    }
}

void q_enqueue(int client) {
    if (q_isInQueue(client)) return;
    g_listQueue.Push(client);
}

void q_clear() {
    g_listQueue.Clear();
}

int q_getClientByPos(int clientPos) {
    if (clientPos < 0 || clientPos >= g_listQueue.Length) return -1;
    return g_listQueue.Get(clientPos);
}

int q_getClientsPos(int client) {
    return g_listQueue.FindValue(client) + 1;
}