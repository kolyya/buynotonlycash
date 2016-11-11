#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <sdktools_functions>

#pragma semicolon 1

public Plugin myinfo =
{
	name = "BuyNotOnlyCash",
	author = "kolyya",
	description = "Buy items for health, speed and so on.",
	version = "0.0.1",
	url = "https://github.com/kolyya/buynotonlycash"
};

ArrayList g_ItemList = null;                	// id покупаемого оружия
new const String:items[][] = 
{
    // Grenades
    "hegrenade"
    ,"flashbang"
    ,"smokegrenade"
    ,"decoy"
    ,"molotov","incgrenade"
    // Equipment
    ,"kevlar"     // vest
    ,"assaultsuit" // vesthelm
    ,"defuser"
    ,"taser"
    // Secondary
    ,"usp_silencer","hkp2000","glock"
    ,"p250" ,"cz75a"
    ,"tec9","fiveseven"
    ,"elite"
    ,"deagle","revolver"
    // Heavy
    ,"nova"
    ,"xm1014"
    ,"mag7","sawedoff"
    ,"m249"
    ,"negev"
    // SMGs
    ,"mac10","mp9"
    ,"mp7"
    ,"ump45"
    ,"bizon"
    ,"p90"
    // Rifles
    ,"galilar","famas"
    ,"ak47","m4a1","m4a1_silencer"
    ,"ssg08"
    ,"aug","sg556"
    ,"awp"
    ,"g3sg1"
    ,"scar20"
} ;

ArrayList g_ParameterList = null;               // список параметров
new const String:parameters[][] = 
{
    "buyzone_only"              // 0 - только в зоне покупки 
    ,"cash"                     // 1 - денег за предмет
    ,"health"                   // 2 - здоровья за предмет
    ,"speed"                    // 3 - скорости за предмет
    ,"regeneration"             // 4 - регена за предмет
    ,"count"                    // 5 - максимальное количество
    ,"team"                     // 6 - id команды
} ;


bool    isInBuyzone[MAXPLAYERS+1] = {false, ...};       // флаг, что игрок в зоне покупки
int     cRegen[MAXPLAYERS+1] = {0, ...};                // количество регена в сек пользователю
int     cMaxHealth[MAXPLAYERS+1] = {0, ...};            // максимальное количество здоровья в сек пользователю
bool    isBuyTime;                                      // время закупа
int     iBuy[MAXPLAYERS+1][sizeof(items)];              // счетчик покупок
int     item;                                           // id предмета, для заполнения конфига
int     ClientHealth                                    // здоровье
        ,ClientCash                                     // деньги
        ,ClientTeam                                     // команда
;
float   ClientSpeed;                                    // скорость
char    g_File[PLATFORM_MAX_PATH];                      // имя файла конфига
any     cfg[sizeof(items)][sizeof(parameters)];         // конфиг
char    g_teamS[PLATFORM_MAX_PATH];                     // название команды Наблюдателей
char    g_teamT[PLATFORM_MAX_PATH];                     // название команды Террористов                               
char    g_teamCT[PLATFORM_MAX_PATH];                    // название команды Контр-Террористов

Handle  g_hTimer;                                       // таймер регена

new     ACCOUNT_OFFSET;


ConVar  g_NotList_Cvar;      //  разрешение покупать не из списка
ConVar  g_File_Cvar;         //  имя файла с конфигом

public void OnPluginStart()
{
    ACCOUNT_OFFSET = FindSendPropInfo("CCSPlayer", "m_iAccount");
    
    int size = ByteCountToCells(PLATFORM_MAX_PATH);
    g_ItemList = new ArrayList(size);
    g_ParameterList = new ArrayList(size);
    
    for(new i = 0; i < sizeof(items); i++)
    {
        PushArrayString(g_ItemList,items[i]);
    }
    
    for(new i = 0; i < sizeof(parameters); i++)
    {
        PushArrayString(g_ParameterList,parameters[i]);
    }
    
    // Cvars
    g_NotList_Cvar = CreateConVar("csgo_bnoc_allow_not_list", "1", "Allow to buy not only from the list", 0, true, 0.00, true, 1.0);
    
    g_File_Cvar = CreateConVar("csgo_bnoc_file", "buynotonlycash_items.cfg", "Name of the con-fig file in the folder addons-sourcemod-configs, like test.cfg",_);
    GetConVarString(g_File_Cvar,g_File,sizeof(g_File));
    
    
    // Events
    HookEvent("enter_buyzone",      Event_EnterBuyZone,         EventHookMode_Post);
    HookEvent("exit_buyzone",       Event_ExitBuyZone,          EventHookMode_Post);
    HookEvent("buytime_ended",      Event_EndedBuyTime,         EventHookMode_Post);
    HookEvent("player_spawned",     Event_PlayerSpawned,        EventHookMode_Post);
    HookEvent("player_death",       Event_PlayerDeath,          EventHookMode_Post);
    HookEvent("round_start",        Event_RoundStart,           EventHookMode_Post);
    HookEvent("round_freeze_end",   Event_RoundFreezeEnd,       EventHookMode_Post);
    
    // конфиг кваров и фраз 
    AutoExecConfig(true, "buynotonlycash");
    LoadTranslations("buynotonlycash.phrases");
    
    // загружаем из файла цены предметов
    loadData();
}


/**
 * Входит в зону покупки
 */
public Action:Event_EnterBuyZone(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    isInBuyzone[client] = true;
}


/**
 * Выходит из зоны покупки
 */
public Action:Event_ExitBuyZone(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    isInBuyzone[client] = false;
}


/**
 * Закончилось время покупки
 */
public Action:Event_EndedBuyTime(Handle:event, const String:name[], bool:dontBroadcast)
{
    isBuyTime = false;
}


/**
 * игрок респавнится
 */
public Action:Event_PlayerSpawned(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    // обнуляем счетчик покупок
    resetIBuy(client);
    
    // устанавливаем его здоровье как максимальное ему
    cMaxHealth[client] = GetClientHealth(client);
    
}


/**
 * игрок умирает
 */
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    // обнуляем счетчик покупок
    resetIBuy(client);
    
    // обнуляем реген в сек
    resetRegen(client);
}


/**
 * начинается раунд
 */
public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{

    // получаем названия команд
    GetTeamName(1, g_teamS, sizeof(g_teamS));
    GetTeamName(2, g_teamT, sizeof(g_teamT));
    GetTeamName(3, g_teamCT, sizeof(g_teamCT));
    
    // останавливаем реген
    KillTimer(g_hTimer);
    
    // включаем время покупки
    isBuyTime = true;

}


/**
 * закончилось время заморозки перед раундом
 */
public Action:Event_RoundFreezeEnd(Handle:event, const String:name[], bool:dontBroadcast)
{

    // запускаем реген
    g_hTimer = CreateTimer(1.0, Timer_Regen, _,TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

}


/**
 * Игрок входит на сервер
 *
 * @param client        clientId
 */
public void OnClientPutInServer(client){
    
    // обнуляем счетчик покупок
    resetIBuy(client);
    
    // обнуляем реген в сек
    resetRegen(client);
    
}

/**
 * При покупке оружия
 *
 * @param client        clentId
 * @param weapon        weaponId: "ak47",...
 */
public Action:CS_OnBuyCommand(client, const String:weapon[])
{
    // игрок в игре?
    if( !IsPlayerAlive(client) )
    {
        return Plugin_Continue;
    } 
    
    PrintToChat(client,"%s",weapon);
    
    // оружие есть в списке?
    if( FindStringInArray(g_ItemList,weapon) >= 0)
    {
    
        // id item
        item = FindStringInArray(g_ItemList,weapon);
        
        // игрок не в зоне покупки и нельзя покупать его за зоной
        if( (!isInBuyzone[client] || !isBuyTime) && cfg[item][0] ) 
        {
        
            PrintToChat(client, "%t", "Only Buyzone", weapon);
            return Plugin_Handled;
        
        }
        
        // Лимит есть и он полон?
        if( cfg[item][5] && (iBuy[client][item] >= cfg[item][5]) ) 
        {
            
            PrintToChat(client, "%t", "Limit", iBuy[client][item], cfg[item][5], weapon);
            return Plugin_Handled;
            
        }
        
        // сколько сейчас денег?
        ClientCash = GetEntData(client, ACCOUNT_OFFSET, 4);
        
        // сколько сейчас здоровья?
        ClientHealth = GetClientHealth(client);
        
        // какая команда у пользователя
        ClientTeam = GetClientTeam(client);
        
        // текущая скорость
        ClientSpeed = GetEntPropFloat(client, Prop_Data,"m_flLaggedMovementValue");
        
        
        // нужны деньги и их не хватает?
        if( cfg[item][1] && (ClientCash - cfg[item][1] < 0) )
        {
        
            PrintToChat(client, "%t", "Few Cash", weapon, ClientCash, cfg[item][1]);
            return Plugin_Handled;
        
        }
        
        // нужно здоровье и его не хватает? 100 - x < 1
        if( cfg[item][2] && (ClientHealth - cfg[item][2] < 1) )
        {
        
            PrintToChat(client, "%t", "Few Health", weapon, ClientHealth, cfg[item][2]);
            return Plugin_Handled;
        
        }
        
        // нужна скорость и ее не хватает? 1.0 - x / 100 < 0
        float speed = float(cfg[item][3]) / 100;
        if( cfg[item][3] && (ClientSpeed - speed < 0) ) 
        {
        
            PrintToChat(client, "%t", "Few Speed", weapon,ClientSpeed,cfg[item][3]);
            return Plugin_Handled;
        
        }
        
        
        // команда важна и неправильная?
        if( cfg[item][6] && ((cfg[item][6] == 1 && ClientTeam != 2) || (cfg[item][6] == 2 && ClientTeam != 3)) )
        {
            
            PrintToChat(client, "%t", "Only Exact Team", weapon, cfg[item][6] == 1?g_teamT:cfg[item][6] == 2?g_teamCT:"");
            return Plugin_Handled;
        
        }  
             
             
        // еще раз проверим игрока 
        if( IsClientInGame(client) && IsPlayerAlive(client) )
        {
            // забираем деньги
            SetEntData(client, ACCOUNT_OFFSET, ClientCash - cfg[item][1]);
            
            // забираем здоровье
            SetEntProp(client, Prop_Data, "m_iHealth", ClientHealth - cfg[item][2]);
            
            // забираем скорость
            SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", ClientSpeed - speed);
            
            // считаем реген
            cRegen[client] = cRegen[client] + cfg[item][4];
            
            // строка под название предмета
            decl String:weaponName[64];
            
            // если kevlar или assaultsuit
            if( StrEqual(weapon,"kevlar") || StrEqual(weapon,"assaultsuit") )
            {
                
                Format(weaponName,sizeof(weaponName),"item_%s",weapon);
         
            // если обычное оружие
            } else 
            {
            
                Format(weaponName,sizeof(weaponName),"weapon_%s",weapon);
            
            }
            
            // выдаем предметто
            GivePlayerItem(client, weaponName);
            
            // счетчик крутим
            iBuy[client][item]++;
        } else 
        {
            
            return Plugin_Continue;
            
        }
    
    // нет в списке, но можно не из списка?
    } else if( g_NotList_Cvar.IntValue ) 
    {
        
        return Plugin_Continue;
    
    }

    return Plugin_Handled;
}


/**
 * Обнуление счетчика покупок клиенту
 * 
 * @param client        clientId
 */
public resetIBuy(client)
{

    for(new i = 0; i < sizeof(items);i++)
    {
        iBuy[client][i] = 0;
    }
    
    return;
    
}


/**
 * Обнуление регена/cек клиенту
 * 
 * @param client        clientId
 */
public resetRegen(client)
{

    cRegen[client] = 0;
    cMaxHealth[client] = 0;
    
    return;
    
}


/**
 * Таймер регена
 */
public Action Timer_Regen(Handle hTimer)
{
    
    for(new i = 1; i < MaxClients;i++)
    {
        if( IsClientInGame(i) && IsPlayerAlive(i) )
        {
            
            // Сколько должно получиться после регена?
            int health = GetClientHealth(i) - cRegen[i];
            
            // у пользователя есть максимальное значение health больше него?
            if(cMaxHealth[i] && health >= cMaxHealth[i])
            {
                
                // дополняем до полного.
                health = cMaxHealth[i];
                
            // значение меньше или равно нулю?    
            } else if(health < 1) 
            {
            
                // убиваем игрока
                FakeClientCommand(i,"kill");
            
                return Plugin_Continue;
            
            }
            
            // приписываем значение
            SetEntProp(i, Prop_Data, "m_iHealth", health );
            
        } 
    }
    
    return Plugin_Continue;
    
}

/**
 * Сканирует файл настроек и заполняет массив cfg[item][parameter]
 */
public loadData(){

    // путь до файла
    new String:sConfigFileName[PLATFORM_MAX_PATH];
    Format(sConfigFileName,sizeof(sConfigFileName),"configs/%s",g_File);
    
    // полный путь до файла
    new String:sConfigFile[PLATFORM_MAX_PATH];
    
    BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), sConfigFileName);

    // если файла нет
    if (!FileExists(sConfigFile)) 
    {
        
        LogError("[SM] Plugin is not running! Could not find file %s", sConfigFile);
        PrintToServer("[SM] Plugin is not running! Could not find file %s", sConfigFile);
        
        SetFailState("Could not find file %s", sConfigFile);
    
    }
    // файл есть, а в порядке ли он?
    else if (!ParseConfigFile(sConfigFile))
    {

        LogError("[SM] Plugin is not running! Failed to parse %s", sConfigFile);
        
        SetFailState("Parse error on file %s", sConfigFile);
    }

    return;
}

stock bool:ParseConfigFile(const String:file[]) 
{

    new Handle:hParser = SMC_CreateParser();
    new String:error[128];
    new line = 0;
    new col = 0;
    
    /**
    Define the parser functions
    */
    SMC_SetReaders(hParser, Config_NewSection, Config_KeyValue, Config_EndSection);
    SMC_SetParseEnd(hParser, Config_End);
    
    /**
    Parse the file and get the result
    */
    new SMCError:result = SMC_ParseFile(hParser, file, line, col);
    CloseHandle(hParser);

    if (result != SMCError_Okay) 
    {
        SMC_GetErrorString(result, error, sizeof(error));
        LogError("%s on line %d, col %d of %s", error, line, col, file);
    }
    
    return (result == SMCError_Okay);
}  

public SMCResult:Config_NewSection(Handle:parser, const String:section[], bool:quotes) 
{
    // если это главная секция, то пропускаем.
    if (StrEqual(section, "Items"))
    {
        return SMCParse_Continue;
    }
    
       
        
    // есть ли секция в списке предметов?
    if ( -1 != FindStringInArray(g_ItemList,section) )
    {
        
        // получаем id для записи
        item = FindStringInArray(g_ItemList,section);
        
    } else {
        
        LogError("Item %s not on the list", section);
    
    }
    
    
    return SMCParse_Continue;
}

public SMCResult:Config_KeyValue(Handle:parser, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
        
    // НЕТ такой в списке параметров?
    if( -1 == FindStringInArray(g_ParameterList,key) ) {
    
        LogError("Key %s not on the list", key);
        return SMCParse_Continue;
    
    // значение НЕ может быть числом?
    } else if( (!StringToInt(value) && !StrEqual(value,"0")) || ( StrEqual(key,"money") && StrEqual(value,"default") ) ) {
    
        LogError("Value %s on key %s can not be a number", value,key);
        return SMCParse_Continue;
    
    // если деньги и они стандартны
    } else if(StrEqual(key,"money") && StrEqual(value,"default")) {
        
        // получаем стандартную цену
        // скоро...
        
        
        int keyId = FindStringInArray(g_ParameterList,key);
        int valueInt = StringToInt(value);
        cfg[item][keyId] = valueInt;
        
    } else {
        
        int keyId = FindStringInArray(g_ParameterList,key);
        int valueInt = StringToInt(value);
        cfg[item][keyId] = valueInt;
        
    }

    return SMCParse_Continue;
}

public SMCResult:Config_EndSection(Handle:parser) 
{
    return SMCParse_Continue;
}

public Config_End(Handle:parser, bool:halted, bool:failed) 
{
    if (failed)
    {
        SetFailState("Plugin configuration error");
    }
}  
