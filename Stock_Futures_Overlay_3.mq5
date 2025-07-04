// Редактирование подтверждено: 2024-06-16
//+------------------------------------------------------------------+
//|                                  Stock_Futures_Overlay_v8.4.mq5 |
//|                                                       Версия 8.4 |
//|                                              Дата: 2025.06.15    |
//|                                                Для MetaTrader 5  |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5
#property strict

// Входные параметры
input datetime BaseDate = D'2024.04.03';      // Базовая дата для расчета фьючерсов
input int      YearsToLoad = 1;               // Глубина истории (лет)
input bool     AutoMultiplier = true;         // Автоматический расчет множителя
input double   ManualMultiplier = 0.01;       // Ручной множитель (если AutoMultiplier = false)
input double   SpreadPct = 0.1;               // Спред для расчета (в процентах)
input double   Commission = 0.05;             // Комиссия брокера (в % от сделки)

// Буферы данных
double StockBuffer[];
double FutBuffer1[], FutBuffer2[], FutBuffer3[], FutBuffer4[];

// Цвета для графиков
color colors[4] = {clrRed, clrBlue, clrGreen, clrOrange};

// Названия фьючерсов и их описания
string futNames[4];
string futDescriptions[4];
double calculatedMultiplier = 1.0;
string futurePrefix = "";

// Флаги загрузки данных и существования фьючерсов
bool dataLoaded[4] = {false, false, false, false};
bool futuresExist[4] = {false, false, false, false};
int loadingProgress[4] = {0, 0, 0, 0};
int loadingAttempts[4] = {0, 0, 0, 0};
bool allDataLoaded = false;

// Полная база данных фьючерсов (код => префикс)
const string futuresDatabase[][2] = {
   {"AFLT", "AF"}, {"ALRS", "AL"}, {"CHMF", "CH"}, {"FEES", "FS"}, 
   {"GAZP", "GZ"}, {"GMKN", "GK"}, {"HYDR", "HY"}, {"LKOH", "LK"}, 
   {"MGNT", "MN"}, {"MOEX", "ME"}, {"MTSS", "MT"}, {"NLMK", "NM"}, 
   {"NVTK", "NK"}, {"ROSN", "RN"}, {"RTKM", "RT"}, {"SBER", "SR"}, 
   {"SNGSP", "SG"}, {"SNGS", "SN"}, {"TATN", "TT"}, {"TATNP", "TP"}, 
   {"TRNF", "TN"}, {"VTBR", "VB"}, {"MAGN", "MG"}, {"PLZL", "PZ"}, 
   {"YDEX", "YD"}, {"AFKS", "AK"}, {"IRAO", "IR"}, {"POLY", "PO"}, 
   {"PIKK", "PI"}, {"SPBE", "SE"}, {"RUAL", "RL"}, {"PHOR", "PH"}, 
   {"SMLT", "SS"}, {"MTLR", "MC"}, {"RSTI", "RE"}, {"SIBN", "SO"}, 
   {"TCSG", "TI"}, {"FIVE", "FV"}, {"VKCO", "VK"}, {"OZON", "OZ"}, 
   {"SPYF", "SF"}, {"NASD", "NA"}, {"POSI", "PS"}, {"STOX", "SX"}, 
   {"HANG", "HS"}, {"DAX", "DX"}, {"NIKK", "N2"}, {"ISKJ", "IS"}, 
   {"WUSH", "WU"}, {"MVID", "MV"}, {"CBOM", "CM"}, {"SGZH", "SZ"}, 
   {"BELU", "BE"}, {"FLOT", "FL"}, {"BSPB", "BS"}, {"BANE", "BN"}, 
   {"KMAZ", "KM"}, {"ASTR", "AS"}, {"SOFL", "S0"}, {"SVCB", "SC"}, 
   {"R2000", "R2"}, {"DJ30", "DJ"}, {"ALIBABA", "BB"}, {"BAIDU", "BD"}, 
   {"RASP", "RA"}, {"FESH", "FE"}, {"RNFT", "RU"}, {"T", "TB"}, 
   {"X5", "X5"}, {"SFIN", "SH"}
};

//+------------------------------------------------------------------+
//| Функция для определения префикса фьючерсов по коду акции         |
//+------------------------------------------------------------------+
string GetFuturePrefix(string symbol)
{
   int dotPos = StringFind(symbol, ".");
   if(dotPos > 0) symbol = StringSubstr(symbol, 0, dotPos);
   
   for(int i = 0; i < ArraySize(futuresDatabase); i++)
   {
      if(futuresDatabase[i][0] == symbol)
         return futuresDatabase[i][1];
   }
   return "";
}

//+------------------------------------------------------------------+
//| Функция для генерации кодов фьючерсов                            |
//+------------------------------------------------------------------+
void GenerateFuturesList()
{
   if(futurePrefix == "")
   {
      Print("Не удалось определить префикс фьючерсов для ", Symbol());
      return;
   }

   MqlDateTime dt;
   TimeToStruct(BaseDate, dt);
   
   string monthCodes = "HMUZ"; 
   string monthNames[] = {"03", "06", "09", "12"};
   
   int year = dt.year;
   int currentMonth = dt.mon;
   int quartal = (currentMonth-1)/3;
   
   for(int i = 0; i < 4; i++)
   {
      int monthIndex = (quartal + i) % 4;
      int yearOffset = (quartal + i) / 4;
      int futureYear = year + yearOffset;
      
      string monthCode = StringSubstr(monthCodes, monthIndex, 1);
      string yearCode = IntegerToString(futureYear % 10);
      
      futNames[i] = futurePrefix + monthCode + yearCode;
      futDescriptions[i] = StringFormat("%s (%s.%02d)", futNames[i], monthNames[monthIndex], futureYear % 100);
      loadingAttempts[i] = 0;
   }
}

//+------------------------------------------------------------------+
//| Функция для создания строки информации                           |
//+------------------------------------------------------------------+
void CreateInfoLine(int lineNum, string text, color clr=clrWhite)
{
   string objName = "InfoLine"+IntegerToString(lineNum);
   ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 50 + lineNum*20);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
}

//+------------------------------------------------------------------+
//| Функция для создания информационной панели                       |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
   // Удаляем старые объекты
   ObjectDelete(0, "InfoHeader");
   for(int i = 0; i < 20; i++) 
       ObjectDelete(0, "InfoLine"+IntegerToString(i));
   
   // Создаем заголовок
   ObjectCreate(0, "InfoHeader", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "InfoHeader", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "InfoHeader", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "InfoHeader", OBJPROP_YDISTANCE, 30);
   ObjectSetString(0, "InfoHeader", OBJPROP_TEXT, "=== Информация (v8.4) ===");
   
   // Основные параметры
   CreateInfoLine(1, "Баз.дата: " + TimeToString(BaseDate, TIME_DATE));
   CreateInfoLine(2, "Множитель: " + DoubleToString(calculatedMultiplier, 5));
   CreateInfoLine(3, "Акция: " + Symbol());
   CreateInfoLine(4, "Префикс: " + futurePrefix);
   CreateInfoLine(5, "Фьючерсы:");
   
   // Статус фьючерсов
   for(int i = 0; i < 4; i++)
   {
      string status;
      color lineColor = colors[i];
      
      if(loadingAttempts[i] >= 10 && !dataLoaded[i])
      {
         status = "✗ (не существует)";
         lineColor = clrGray;
      }
      else if(!futuresExist[i]) 
      {
         status = "? (проверка)";
      }
      else if(dataLoaded[i]) 
      {
         status = "✓ (загружено)";
      }
      else 
      {
         status = StringFormat("%d%% (%d/10)", loadingProgress[i], loadingAttempts[i]);
      }
      
      CreateInfoLine(6+i, StringFormat("  %s: %s", futDescriptions[i], status), lineColor);
   }
   
   int lineNum = 11;
   CreateInfoLine(lineNum++, allDataLoaded ? "Все данные загружены" : "Загрузка данных...", 
                 allDataLoaded ? clrGreen : clrGold);
   
   // Блок доходности (добавляем только если данные загружены)
   if(allDataLoaded)
   {
      string stockSymbol = Symbol();
      CreateInfoLine(lineNum++, "=== Доходность ===", clrGold);
      
      for(int i = 0; i < 4; i++)
      {
         if(futuresExist[i] && dataLoaded[i])
         {
            datetime expiration = GetFutureExpiration(futNames[i]);
            if(expiration > 0)
            {
               // Расчет доходности фьючерса
               double yield = CalculateFutureYield(stockSymbol, futNames[i], calculatedMultiplier, SpreadPct);
               CreateInfoLine(lineNum++, 
                  StringFormat("  %s: %.2f%% год. (до %s)", 
                     futDescriptions[i], 
                     yield, 
                     TimeToString(expiration, TIME_DATE)
                  ), 
                  colors[i]);
               
               // Расчет стратегии
               double stockPrice = SymbolInfoDouble(stockSymbol, SYMBOL_BID);
               double futurePrice = SymbolInfoDouble(futNames[i], SYMBOL_ASK);
               double profit, annualYield;
               
               if(CalculateHedgeStrategyYield(
                  stockSymbol, futNames[i], 
                  stockPrice, futurePrice, 
                  calculatedMultiplier, expiration,
                  profit, annualYield) != 0)
               {
                  double margin = SymbolInfoDouble(futNames[i], SYMBOL_MARGIN_INITIAL);
                  if(margin <= 0) margin = futurePrice * calculatedMultiplier * 100 * 0.25;
                  
                  CreateInfoLine(lineNum++, "  Стратегия (100 акций + 1 фьючерс):", colors[i]);
                  CreateInfoLine(lineNum++, StringFormat("    Прибыль: %.2f ₽", profit), colors[i]);
                  CreateInfoLine(lineNum++, 
                     StringFormat("    Доходность: %.2f%% (год. %.2f%%)", 
                        (profit / (100*stockPrice + margin)) * 100, 
                        annualYield
                     ), 
                     colors[i]);
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
//| Функция проверки загрузки данных                                 |
//+------------------------------------------------------------------+
bool CheckDataLoading()
{
    if(allDataLoaded) return true;
    
    datetime start_date = BaseDate - YearsToLoad*365*24*60*60;
    allDataLoaded = true;
    
    for(int i = 0; i < 4; i++)
    {
        if(loadingAttempts[i] >= 10 && !dataLoaded[i])
        {
            futuresExist[i] = false;
            continue;
        }
        
        if(dataLoaded[i]) continue;
        
        if(Bars(futNames[i], PERIOD_D1) > 0)
        {
            datetime firstBarTime = iTime(futNames[i], PERIOD_D1, Bars(futNames[i], PERIOD_D1)-1);
            if(firstBarTime <= start_date)
            {
                dataLoaded[i] = true;
                loadingProgress[i] = 100;
                futuresExist[i] = true;
            }
            else
            {
                loadingProgress[i] = (int)(100.0 * (1.0 - (double)(start_date - firstBarTime) / (double)(TimeCurrent() - firstBarTime)));
                if(loadingProgress[i] >= 100)
                {
                    dataLoaded[i] = true;
                    loadingProgress[i] = 100;
                    futuresExist[i] = true;
                }
                allDataLoaded = false;
            }
        }
        else
        {
            allDataLoaded = false;
        }
    }
    
    CreateInfoPanel();
    return allDataLoaded;
}

// Остальные функции (GetFutureExpiration, CalculateFutureYield, CalculateHedgeStrategyYield) 
// остаются без изменений и должны быть добавлены перед OnInit()

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    CheckDataLoading();
}

//+------------------------------------------------------------------+
//| Функция для получения даты экспирации фьючерса                   |
//+------------------------------------------------------------------+
datetime GetFutureExpiration(string symbol)
{
    datetime expiration = (datetime)SymbolInfoInteger(symbol, SYMBOL_EXPIRATION_TIME);
    if(expiration > 0) return expiration;
    
    string monthCode = StringSubstr(symbol, 2, 1);
    string yearCode = StringSubstr(symbol, 3, 1);
    
    int month = 0;
    int year = 2000 + (int)StringToInteger(yearCode);
    
    if(TimeCurrent() > StringToTime(IntegerToString(year) + ".01.01"))
        year++;
    
    if(monthCode == "H") month = 3;
    else if(monthCode == "M") month = 6;
    else if(monthCode == "U") month = 9;
    else if(monthCode == "Z") month = 12;
    
    if(month > 0 && year > 0)
        return StringToTime(IntegerToString(year) + "." + IntegerToString(month) + ".15");
    
    return 0;
}

//+------------------------------------------------------------------+
//| Функция для расчета доходности фьючерса                          |
//+------------------------------------------------------------------+
double CalculateFutureYield(string stockSymbol, string futureSymbol, double multiplier, double spreadPct)
{
    double stockBid = SymbolInfoDouble(stockSymbol, SYMBOL_BID);
    double stockAsk = SymbolInfoDouble(stockSymbol, SYMBOL_ASK);
    double stockPrice = (stockBid + stockAsk) / 2;
    
    double futureBid = SymbolInfoDouble(futureSymbol, SYMBOL_BID);
    double futureAsk = SymbolInfoDouble(futureSymbol, SYMBOL_ASK);
    double futurePrice = (futureBid + futureAsk) / 2;
    
    datetime expiration = GetFutureExpiration(futureSymbol);
    if(expiration == 0) return 0;
    
    double yearsToExpiration = (double)(expiration - TimeCurrent()) / (365.0 * 24 * 60 * 60);
    if(yearsToExpiration <= 0) return 0;
    
    double adjustedStockPrice = stockPrice * (1 + spreadPct/100.0);
    double adjustedFuturePrice = futurePrice * (1 - spreadPct/100.0) * multiplier;
    
    if(adjustedStockPrice <= 0 || adjustedFuturePrice <= 0) return 0;
    
    double profit = adjustedFuturePrice - adjustedStockPrice;
    return (profit / adjustedStockPrice) * (1.0 / yearsToExpiration) * 100;
}

//+------------------------------------------------------------------+
//| Расчет доходности стратегии "акция + короткий фьючерс"           |
//+------------------------------------------------------------------+
double CalculateHedgeStrategyYield(
    string stockSymbol, string futureSymbol,
    double stockPrice, double futurePrice,
    double multiplier, datetime expiration,
    double& outProfit, double& outAnnualYield
)
{
    double stockBid = SymbolInfoDouble(stockSymbol, SYMBOL_BID);
    double stockAsk = SymbolInfoDouble(stockSymbol, SYMBOL_ASK);
    double currentStockPrice = (stockBid + stockAsk) / 2;
    
    double futureBid = SymbolInfoDouble(futureSymbol, SYMBOL_BID);
    double futureAsk = SymbolInfoDouble(futureSymbol, SYMBOL_ASK);
    double currentFuturePrice = (futureBid + futureAsk) / 2;
    
    double expirationStockPrice = currentStockPrice;
    double expirationFuturePrice = expirationStockPrice / multiplier;
    
    double stockProfit = (expirationStockPrice - stockPrice) * 100;
    double futureProfit = (futurePrice - expirationFuturePrice) * multiplier * 100;
    double commission = (stockPrice * 100 + expirationStockPrice * 100) * (Commission/100.0) + 
                       (futurePrice * 100 + expirationFuturePrice * 100) * (Commission/100.0);
    
    outProfit = stockProfit + futureProfit - commission;
    
    double stockCost = 100 * stockPrice;
    double futureMargin = SymbolInfoDouble(futureSymbol, SYMBOL_MARGIN_INITIAL);
    if(futureMargin <= 0) futureMargin = futurePrice * multiplier * 100 * 0.25;
    
    double totalCost = stockCost + futureMargin;
    double periodYield = (outProfit / totalCost) * 100;
    
    double daysToExp = (double)(expiration - TimeCurrent()) / (24 * 60 * 60);
    if(daysToExp <= 0) return 0;
    
    outAnnualYield = (MathPow(1 + periodYield/100, 365.0/daysToExp) - 1) * 100;
    return periodYield;
}



//+------------------------------------------------------------------+
//| Функция OnInit                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    futurePrefix = GetFuturePrefix(Symbol());
    if(futurePrefix == "")
    {
        Alert("Не найден префикс фьючерсов для ", Symbol());
        return INIT_FAILED;
    }

    GenerateFuturesList();
    
    for(int i = 0; i < 4; i++)
    {
        if(!SymbolSelect(futNames[i], true))
        {
            int error = GetLastError();
            if(error == 4305)
            {
                loadingAttempts[i] = 10;
                futuresExist[i] = false;
                Print("Фьючерс ", futNames[i], " не существует");
            }
        }
    }
    
    calculatedMultiplier = ManualMultiplier;
    
    SetIndexBuffer(0, StockBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, FutBuffer1, INDICATOR_DATA);
    SetIndexBuffer(2, FutBuffer2, INDICATOR_DATA);
    SetIndexBuffer(3, FutBuffer3, INDICATOR_DATA);
    SetIndexBuffer(4, FutBuffer4, INDICATOR_DATA);

    PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
    PlotIndexSetInteger(0, PLOT_LINE_COLOR, clrBlack);
    PlotIndexSetString(0, PLOT_LABEL, Symbol());

    for(int i = 1; i <= 4; i++)
    {
        PlotIndexSetInteger(i, PLOT_DRAW_TYPE, DRAW_LINE);
        PlotIndexSetInteger(i, PLOT_LINE_COLOR, colors[i-1]);
        PlotIndexSetString(i, PLOT_LABEL, futNames[i-1]);
        
        if(loadingAttempts[i-1] >= 10 && !dataLoaded[i-1])
            PlotIndexSetInteger(i, PLOT_DRAW_TYPE, DRAW_NONE);
    }

    CreateInfoPanel();
    EventSetTimer(1);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if(!CheckDataLoading())
    {
        ArrayInitialize(StockBuffer, EMPTY_VALUE);
        ArrayInitialize(FutBuffer1, EMPTY_VALUE);
        ArrayInitialize(FutBuffer2, EMPTY_VALUE);
        ArrayInitialize(FutBuffer3, EMPTY_VALUE);
        ArrayInitialize(FutBuffer4, EMPTY_VALUE);
        return rates_total;
    }
    
    datetime start_date = BaseDate - YearsToLoad*365*24*60*60;
    
    for(int i = 0; i < rates_total; i++)
    {
        if(time[i] >= start_date)
        {
            StockBuffer[i] = close[i];
            
            for(int j = 0; j < 4; j++)
            {
                if(!futuresExist[j] || !dataLoaded[j])
                {
                    switch(j)
                    {
                        case 0: FutBuffer1[i] = EMPTY_VALUE; break;
                        case 1: FutBuffer2[i] = EMPTY_VALUE; break;
                        case 2: FutBuffer3[i] = EMPTY_VALUE; break;
                        case 3: FutBuffer4[i] = EMPTY_VALUE; break;
                    }
                    continue;
                }
                
                int shift = iBarShift(futNames[j], PERIOD_D1, time[i]);
                double futValue = (shift >= 0) ? iClose(futNames[j], PERIOD_D1, shift) * calculatedMultiplier : EMPTY_VALUE;
                
                switch(j)
                {
                    case 0: FutBuffer1[i] = futValue; break;
                    case 1: FutBuffer2[i] = futValue; break;
                    case 2: FutBuffer3[i] = futValue; break;
                    case 3: FutBuffer4[i] = futValue; break;
                }
            }
        }
        else
        {
            StockBuffer[i] = EMPTY_VALUE;
            FutBuffer1[i] = EMPTY_VALUE;
            FutBuffer2[i] = EMPTY_VALUE;
            FutBuffer3[i] = EMPTY_VALUE;
            FutBuffer4[i] = EMPTY_VALUE;
        }
    }
    return rates_total;
}

//+------------------------------------------------------------------+
//| Функция OnDeinit                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    for(int i = 0; i < 4; i++)
        if(futuresExist[i])
            SymbolSelect(futNames[i], false);
    
    ObjectDelete(0, "InfoHeader");
    for(int i = 0; i < 20; i++) 
        ObjectDelete(0, "InfoLine"+IntegerToString(i));
    
    EventKillTimer();
}
