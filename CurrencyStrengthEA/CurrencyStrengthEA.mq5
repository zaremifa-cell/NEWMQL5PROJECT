//+------------------------------------------------------------------+
//|                                          CurrencyStrengthEA.mq5  |
//|                         Currency Strength Trend-Following EA     |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Currency Strength EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// Общи настройки
input string  SymbolsList      = "EURUSD,GBPUSD,USDJPY,USDCHF,USDCAD,AUDUSD,NZDUSD,EURJPY,EURGBP,EURAUD,EURNZD,EURCAD,EURCHF,GBPJPY,GBPAUD,GBPNZD,GBPCAD,GBPCHF,AUDJPY,NZDJPY,CADJPY,CHFJPY,AUDCAD,AUDCHF,NZDCAD,NZDCHF,CADCHF"; 
input ENUM_TIMEFRAMES Timeframe = PERIOD_H4;

// Параметри за strength/momentum
input int     StrengthLookbackShort = 10;   // Кратък период за strength
input int     StrengthLookbackLong  = 50;   // Дълъг период за strength
input int     MomentumSmoothing     = 5;    // EMA период за momentum

// Избор на позиции
input int     MaxPairsToTrade      = 3;     // Макс. брой двойки едновременно
input double  RiskPerTradePercent  = 1.0;   // Риск % от equity на сделка
input double  MaxTotalRiskPercent  = 10.0;  // Макс. общ риск %

// Волатилност и стопове
input int     ATR_Period           = 20;    // ATR период
input double  ATR_MultiplierSL     = 3.0;   // SL = ATR * множител
input double  ATR_MultiplierTP     = 0.0;   // TP = ATR * множител (0 = без TP)

// Глобален basket контрол
input bool    UseEquityTP          = true;  // Използвай Equity TP
input double  EquityTP_Percent     = 5.0;   // Equity TP %
input bool    UseEquitySL          = false; // Използвай Equity SL
input double  EquitySL_Percent     = 5.0;   // Equity SL %

// Технически
input int     RecalcMinutes        = 60;    // Преизчисляване на всеки X минути
input bool    OnlyOnNewBar         = true;  // Входове само на нов бар
input int     MagicNumber          = 123456;// Magic number за идентификация

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

// Списъци
string         g_Symbols[];                    // Масив със символи
string         g_Currencies[8] = {"EUR","USD","GBP","JPY","CHF","CAD","AUD","NZD"};
int            g_SymbolCount = 0;
int            g_CurrencyCount = 8;

// Currency Strength данни
double         g_CurrencyStrengthShort[];      // Кратка сила по валута
double         g_CurrencyStrengthLong[];       // Дълга сила по валута
double         g_CurrencyMomentum[];           // Momentum по валута
double         g_CurrencyMomentumSmoothed[];   // Сгладен momentum

// Equity контрол
double         g_StartEquity = 0;
datetime       g_LastRecalcTime = 0;
datetime       g_LastBarTime = 0;
bool           g_NeedRecalc = true;

// ATR handles
int            g_ATR_Handles[];

// Trade object
CTrade         g_Trade;

//+------------------------------------------------------------------+
//| INITIALIZATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Зареди символите
   if(!ParseSymbolsList())
   {
      Print("ERROR: Failed to parse symbols list");
      return INIT_FAILED;
   }
   
   // Инициализирай масивите за валутна сила
   ArrayResize(g_CurrencyStrengthShort, g_CurrencyCount);
   ArrayResize(g_CurrencyStrengthLong, g_CurrencyCount);
   ArrayResize(g_CurrencyMomentum, g_CurrencyCount);
   ArrayResize(g_CurrencyMomentumSmoothed, g_CurrencyCount);
   ArrayInitialize(g_CurrencyStrengthShort, 0);
   ArrayInitialize(g_CurrencyStrengthLong, 0);
   ArrayInitialize(g_CurrencyMomentum, 0);
   ArrayInitialize(g_CurrencyMomentumSmoothed, 0);
   
   // Създай ATR handles за всички символи
   ArrayResize(g_ATR_Handles, g_SymbolCount);
   for(int i = 0; i < g_SymbolCount; i++)
   {
      g_ATR_Handles[i] = iATR(g_Symbols[i], Timeframe, ATR_Period);
      if(g_ATR_Handles[i] == INVALID_HANDLE)
      {
         Print("ERROR: Cannot create ATR handle for ", g_Symbols[i]);
         return INIT_FAILED;
      }
   }
   
   // Запомни стартовия equity
   g_StartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Настрой таймер
   EventSetTimer(RecalcMinutes * 60);
   
   // Настрой trade object
   g_Trade.SetExpertMagicNumber(MagicNumber);
   g_Trade.SetDeviationInPoints(10);
   g_Trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   Print("=== Currency Strength EA Initialized ===");
   Print("Symbols: ", g_SymbolCount);
   Print("Start Equity: ", g_StartEquity);
   Print("Timeframe: ", EnumToString(Timeframe));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   // Освободи ATR handles
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_ATR_Handles[i] != INVALID_HANDLE)
         IndicatorRelease(g_ATR_Handles[i]);
   }
   
   Print("=== Currency Strength EA Deinitialized ===");
}

//+------------------------------------------------------------------+
//| TIMER EVENT                                                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_NeedRecalc = true;
}

//+------------------------------------------------------------------+
//| MAIN TICK FUNCTION                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Проверка за нов бар
   if(OnlyOnNewBar && !IsNewBar())
      return;
   
   // Проверка за Equity TP/SL първо
   if(CheckEquityTPSL())
      return; // Ако сме затворили всичко, спри за този тик
   
   // Преизчисли strength/momentum ако е нужно
   if(g_NeedRecalc || TimeCurrent() - g_LastRecalcTime > RecalcMinutes * 60)
   {
      CalculateCurrencyStrength();
      CalculateCurrencyMomentum();
      LogCurrencyRankings();
      g_LastRecalcTime = TimeCurrent();
      g_NeedRecalc = false;
   }
   
   // Провери за изходи от съществуващи позиции
   CheckExitSignals();
   
   // Избери двойки за търговия и изпълни входове
   ProcessEntrySignals();
}

//+------------------------------------------------------------------+
//| MODULE 1: PARSE SYMBOLS LIST                                      |
//+------------------------------------------------------------------+
bool ParseSymbolsList()
{
   string symbols[];
   int count = StringSplit(SymbolsList, ',', symbols);
   
   if(count <= 0)
      return false;
   
   ArrayResize(g_Symbols, count);
   g_SymbolCount = 0;
   
   for(int i = 0; i < count; i++)
   {
      string sym = StringTrimLeft(StringTrimRight(symbols[i]));
      
      // Провери дали символът съществува
      if(SymbolSelect(sym, true))
      {
         g_Symbols[g_SymbolCount] = sym;
         g_SymbolCount++;
      }
      else
      {
         Print("WARNING: Symbol not found: ", sym);
      }
   }
   
   ArrayResize(g_Symbols, g_SymbolCount);
   return g_SymbolCount > 0;
}

//+------------------------------------------------------------------+
//| MODULE 2: CHECK NEW BAR                                           |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, Timeframe, 0);
   
   if(currentBarTime != g_LastBarTime)
   {
      g_LastBarTime = currentBarTime;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 3: CALCULATE CURRENCY STRENGTH                             |
//+------------------------------------------------------------------+
void CalculateCurrencyStrength()
{
   // Временни масиви за натрупване
   double strengthSumShort[];
   double strengthSumLong[];
   int strengthCount[];
   
   ArrayResize(strengthSumShort, g_CurrencyCount);
   ArrayResize(strengthSumLong, g_CurrencyCount);
   ArrayResize(strengthCount, g_CurrencyCount);
   ArrayInitialize(strengthSumShort, 0);
   ArrayInitialize(strengthSumLong, 0);
   ArrayInitialize(strengthCount, 0);
   
   // За всеки символ изчисли log returns и ги разпредели по валути
   for(int s = 0; s < g_SymbolCount; s++)
   {
      string symbol = g_Symbols[s];
      string baseCcy, quoteCcy;
      
      if(!GetBaseCurrency(symbol, baseCcy) || !GetQuoteCurrency(symbol, quoteCcy))
         continue;
      
      int baseIdx = GetCurrencyIndex(baseCcy);
      int quoteIdx = GetCurrencyIndex(quoteCcy);
      
      if(baseIdx < 0 || quoteIdx < 0)
         continue;
      
      // Изчисли log returns за кратък и дълъг период
      double logRetShort = CalculateLogReturn(symbol, StrengthLookbackShort);
      double logRetLong = CalculateLogReturn(symbol, StrengthLookbackLong);
      
      // Base валута получава положителен return
      strengthSumShort[baseIdx] += logRetShort;
      strengthSumLong[baseIdx] += logRetLong;
      strengthCount[baseIdx]++;
      
      // Quote валута получава отрицателен return
      strengthSumShort[quoteIdx] -= logRetShort;
      strengthSumLong[quoteIdx] -= logRetLong;
      strengthCount[quoteIdx]++;
   }
   
   // Изчисли средната сила за всяка валута
   for(int c = 0; c < g_CurrencyCount; c++)
   {
      if(strengthCount[c] > 0)
      {
         g_CurrencyStrengthShort[c] = strengthSumShort[c] / strengthCount[c];
         g_CurrencyStrengthLong[c] = strengthSumLong[c] / strengthCount[c];
      }
      else
      {
         g_CurrencyStrengthShort[c] = 0;
         g_CurrencyStrengthLong[c] = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| MODULE 4: CALCULATE LOG RETURN                                    |
//+------------------------------------------------------------------+
double CalculateLogReturn(string symbol, int period)
{
   double closeNow = iClose(symbol, Timeframe, 0);
   double closePast = iClose(symbol, Timeframe, period);
   
   if(closePast <= 0 || closeNow <= 0)
      return 0;
   
   return MathLog(closeNow / closePast);
}

//+------------------------------------------------------------------+
//| MODULE 5: CALCULATE CURRENCY MOMENTUM                             |
//+------------------------------------------------------------------+
void CalculateCurrencyMomentum()
{
   static double prevMomentumSmoothed[];
   
   if(ArraySize(prevMomentumSmoothed) != g_CurrencyCount)
   {
      ArrayResize(prevMomentumSmoothed, g_CurrencyCount);
      ArrayInitialize(prevMomentumSmoothed, 0);
   }
   
   double emaMultiplier = 2.0 / (MomentumSmoothing + 1.0);
   
   for(int c = 0; c < g_CurrencyCount; c++)
   {
      // Momentum = кратка сила - дълга сила
      g_CurrencyMomentum[c] = g_CurrencyStrengthShort[c] - g_CurrencyStrengthLong[c];
      
      // EMA smoothing
      if(prevMomentumSmoothed[c] == 0)
         g_CurrencyMomentumSmoothed[c] = g_CurrencyMomentum[c];
      else
         g_CurrencyMomentumSmoothed[c] = g_CurrencyMomentum[c] * emaMultiplier + 
                                          prevMomentumSmoothed[c] * (1 - emaMultiplier);
      
      prevMomentumSmoothed[c] = g_CurrencyMomentumSmoothed[c];
   }
}

//+------------------------------------------------------------------+
//| MODULE 6: GET CURRENCY INDEX                                      |
//+------------------------------------------------------------------+
int GetCurrencyIndex(string currency)
{
   for(int i = 0; i < g_CurrencyCount; i++)
   {
      if(g_Currencies[i] == currency)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| MODULE 7: GET BASE CURRENCY FROM SYMBOL                           |
//+------------------------------------------------------------------+
bool GetBaseCurrency(string symbol, string &base)
{
   if(StringLen(symbol) < 6)
      return false;
   
   base = StringSubstr(symbol, 0, 3);
   return true;
}

//+------------------------------------------------------------------+
//| MODULE 8: GET QUOTE CURRENCY FROM SYMBOL                          |
//+------------------------------------------------------------------+
bool GetQuoteCurrency(string symbol, string &quote)
{
   if(StringLen(symbol) < 6)
      return false;
   
   quote = StringSubstr(symbol, 3, 3);
   return true;
}

//+------------------------------------------------------------------+
//| MODULE 9: GET STRONGEST AND WEAKEST CURRENCIES                    |
//+------------------------------------------------------------------+
void GetStrongestWeakest(int &strongIdx[], int &weakIdx[], int count)
{
   // Създай масив с индекси и momentum стойности
   int indices[];
   double momValues[];
   ArrayResize(indices, g_CurrencyCount);
   ArrayResize(momValues, g_CurrencyCount);
   
   for(int i = 0; i < g_CurrencyCount; i++)
   {
      indices[i] = i;
      momValues[i] = g_CurrencyMomentumSmoothed[i];
   }
   
   // Bubble sort по momentum (descending)
   for(int i = 0; i < g_CurrencyCount - 1; i++)
   {
      for(int j = i + 1; j < g_CurrencyCount; j++)
      {
         if(momValues[j] > momValues[i])
         {
            double tempMom = momValues[i];
            momValues[i] = momValues[j];
            momValues[j] = tempMom;
            
            int tempIdx = indices[i];
            indices[i] = indices[j];
            indices[j] = tempIdx;
         }
      }
   }
   
   // Вземи top N като най-силни
   ArrayResize(strongIdx, count);
   ArrayResize(weakIdx, count);
   
   for(int i = 0; i < count && i < g_CurrencyCount; i++)
   {
      strongIdx[i] = indices[i];
      weakIdx[i] = indices[g_CurrencyCount - 1 - i];
   }
}

//+------------------------------------------------------------------+
//| MODULE 10: FIND TRADEABLE PAIRS                                   |
//+------------------------------------------------------------------+
void FindTradeablePairs(int &strongIdx[], int &weakIdx[], string &pairs[], int &directions[])
{
   string tempPairs[];
   int tempDirs[];
   double tempScores[];
   int pairCount = 0;
   
   int strongCount = ArraySize(strongIdx);
   int weakCount = ArraySize(weakIdx);
   
   ArrayResize(tempPairs, strongCount * weakCount);
   ArrayResize(tempDirs, strongCount * weakCount);
   ArrayResize(tempScores, strongCount * weakCount);
   
   for(int s = 0; s < strongCount; s++)
   {
      for(int w = 0; w < weakCount; w++)
      {
         string strongCcy = g_Currencies[strongIdx[s]];
         string weakCcy = g_Currencies[weakIdx[w]];
         
         if(strongCcy == weakCcy)
            continue;
         
         // Търси символ strongCcy + weakCcy
         string symbol1 = strongCcy + weakCcy;
         string symbol2 = weakCcy + strongCcy;
         
         int symIdx1 = FindSymbolIndex(symbol1);
         int symIdx2 = FindSymbolIndex(symbol2);
         
         if(symIdx1 >= 0)
         {
            tempPairs[pairCount] = symbol1;
            tempDirs[pairCount] = 1; // BUY (strong е base)
            tempScores[pairCount] = MathAbs(g_CurrencyMomentumSmoothed[strongIdx[s]] - 
                                            g_CurrencyMomentumSmoothed[weakIdx[w]]);
            pairCount++;
         }
         else if(symIdx2 >= 0)
         {
            tempPairs[pairCount] = symbol2;
            tempDirs[pairCount] = -1; // SELL (strong е quote)
            tempScores[pairCount] = MathAbs(g_CurrencyMomentumSmoothed[strongIdx[s]] - 
                                            g_CurrencyMomentumSmoothed[weakIdx[w]]);
            pairCount++;
         }
      }
   }
   
   // Сортирай по score (descending) и вземи top MaxPairsToTrade
   for(int i = 0; i < pairCount - 1; i++)
   {
      for(int j = i + 1; j < pairCount; j++)
      {
         if(tempScores[j] > tempScores[i])
         {
            string tp = tempPairs[i]; tempPairs[i] = tempPairs[j]; tempPairs[j] = tp;
            int td = tempDirs[i]; tempDirs[i] = tempDirs[j]; tempDirs[j] = td;
            double ts = tempScores[i]; tempScores[i] = tempScores[j]; tempScores[j] = ts;
         }
      }
   }
   
   int resultCount = MathMin(pairCount, MaxPairsToTrade);
   ArrayResize(pairs, resultCount);
   ArrayResize(directions, resultCount);
   
   for(int i = 0; i < resultCount; i++)
   {
      pairs[i] = tempPairs[i];
      directions[i] = tempDirs[i];
   }
}

//+------------------------------------------------------------------+
//| MODULE 11: FIND SYMBOL INDEX                                      |
//+------------------------------------------------------------------+
int FindSymbolIndex(string symbol)
{
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Symbols[i] == symbol)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| MODULE 12: PROCESS ENTRY SIGNALS                                  |
//+------------------------------------------------------------------+
void ProcessEntrySignals()
{
   // Вземи най-силни и най-слаби валути
   int strongIdx[], weakIdx[];
   GetStrongestWeakest(strongIdx, weakIdx, 2); // Top 2 от всяка страна
   
   // Намери търгуеми двойки
   string pairs[];
   int directions[];
   FindTradeablePairs(strongIdx, weakIdx, pairs, directions);
   
   // Провери общия риск
   double currentTotalRisk = CalculateTotalRisk();
   
   // Обработи всяка двойка
   for(int i = 0; i < ArraySize(pairs); i++)
   {
      string symbol = pairs[i];
      int direction = directions[i]; // 1 = BUY, -1 = SELL
      
      // Провери за съществуваща позиция
      int existingDir = GetExistingPositionDirection(symbol);
      
      if(existingDir == direction)
      {
         // Вече имаме позиция в същата посока
         continue;
      }
      else if(existingDir != 0 && existingDir != direction)
      {
         // Имаме позиция в обратна посока - затвори я
         ClosePositionBySymbol(symbol, "Momentum reversal");
         continue; // Чакаме следващ бар за нов вход
      }
      
      // Провери общия риск
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double tradeRisk = equity * RiskPerTradePercent / 100.0;
      
      if(currentTotalRisk + tradeRisk > equity * MaxTotalRiskPercent / 100.0)
      {
         Print("Max total risk reached. Skipping entry for ", symbol);
         continue;
      }
      
      // Открий позиция
      OpenPosition(symbol, direction);
      currentTotalRisk += tradeRisk;
   }
}

//+------------------------------------------------------------------+
//| MODULE 13: CHECK EXIT SIGNALS                                     |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   int total = PositionsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      long posType = PositionGetInteger(POSITION_TYPE);
      
      string baseCcy, quoteCcy;
      if(!GetBaseCurrency(symbol, baseCcy) || !GetQuoteCurrency(symbol, quoteCcy))
         continue;
      
      int baseIdx = GetCurrencyIndex(baseCcy);
      int quoteIdx = GetCurrencyIndex(quoteCcy);
      
      if(baseIdx < 0 || quoteIdx < 0)
         continue;
      
      double baseMom = g_CurrencyMomentumSmoothed[baseIdx];
      double quoteMom = g_CurrencyMomentumSmoothed[quoteIdx];
      
      bool shouldClose = false;
      string reason = "";
      
      if(posType == POSITION_TYPE_BUY)
      {
         // За BUY: base трябва да е силен, quote слаб
         if(baseMom < 0)
         {
            shouldClose = true;
            reason = StringFormat("Base %s momentum turned negative (%.5f)", baseCcy, baseMom);
         }
         else if(quoteMom > 0)
         {
            shouldClose = true;
            reason = StringFormat("Quote %s momentum turned positive (%.5f)", quoteCcy, quoteMom);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         // За SELL: base трябва да е слаб, quote силен
         if(baseMom > 0)
         {
            shouldClose = true;
            reason = StringFormat("Base %s momentum turned positive (%.5f)", baseCcy, baseMom);
         }
         else if(quoteMom < 0)
         {
            shouldClose = true;
            reason = StringFormat("Quote %s momentum turned negative (%.5f)", quoteCcy, quoteMom);
         }
      }
      
      if(shouldClose)
      {
         ClosePositionByTicket(ticket, reason);
      }
   }
}

//+------------------------------------------------------------------+
//| MODULE 14: OPEN POSITION                                          |
//+------------------------------------------------------------------+
bool OpenPosition(string symbol, int direction)
{
   // Изчисли ATR
   int symIdx = FindSymbolIndex(symbol);
   if(symIdx < 0) return false;
   
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   if(CopyBuffer(g_ATR_Handles[symIdx], 0, 0, 1, atrBuffer) <= 0)
   {
      Print("ERROR: Cannot get ATR for ", symbol);
      return false;
   }
   
   double atr = atrBuffer[0];
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Изчисли SL distance
   double slDistance = atr * ATR_MultiplierSL;
   double slPoints = slDistance / point;
   
   // Изчисли lot size
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * RiskPerTradePercent / 100.0;
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   double lot = 0;
   if(tickValue > 0 && slPoints > 0)
   {
      lot = riskAmount / (slPoints * tickValue * (point / tickSize));
   }
   
   // Закръгли lot
   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   
   if(lot < minLot)
   {
      Print("Calculated lot too small for ", symbol);
      return false;
   }
   
   // Определи цени
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double sl, tp;
   
   string baseCcy, quoteCcy;
   GetBaseCurrency(symbol, baseCcy);
   GetQuoteCurrency(symbol, quoteCcy);
   
   int baseIdx = GetCurrencyIndex(baseCcy);
   int quoteIdx = GetCurrencyIndex(quoteCcy);
   
   string reason = StringFormat("%s strong (%.5f), %s weak (%.5f)", 
                                 baseCcy, g_CurrencyMomentumSmoothed[baseIdx],
                                 quoteCcy, g_CurrencyMomentumSmoothed[quoteIdx]);
   
   bool result = false;
   
   if(direction > 0) // BUY
   {
      sl = NormalizeDouble(ask - slDistance, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
      tp = ATR_MultiplierTP > 0 ? NormalizeDouble(ask + atr * ATR_MultiplierTP, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)) : 0;
      
      result = g_Trade.Buy(lot, symbol, ask, sl, tp, "CS EA");
      
      if(result)
         Print("ENTRY BUY ", symbol, " Lot: ", lot, " SL: ", sl, " Reason: ", reason);
   }
   else // SELL
   {
      sl = NormalizeDouble(bid + slDistance, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
      tp = ATR_MultiplierTP > 0 ? NormalizeDouble(bid - atr * ATR_MultiplierTP, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)) : 0;
      
      result = g_Trade.Sell(lot, symbol, bid, sl, tp, "CS EA");
      
      if(result)
         Print("ENTRY SELL ", symbol, " Lot: ", lot, " SL: ", sl, " Reason: ", reason);
   }
   
   if(!result)
   {
      Print("ERROR: Trade failed for ", symbol, " Error: ", GetLastError());
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| MODULE 15: GET EXISTING POSITION DIRECTION                        |
//+------------------------------------------------------------------+
int GetExistingPositionDirection(string symbol)
{
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) == symbol)
      {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            return 1;
         else
            return -1;
      }
   }
   
   return 0; // Няма позиция
}

//+------------------------------------------------------------------+
//| MODULE 16: CLOSE POSITION BY SYMBOL                               |
//+------------------------------------------------------------------+
bool ClosePositionBySymbol(string symbol, string reason)
{
   int total = PositionsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      if(PositionGetString(POSITION_SYMBOL) == symbol)
      {
         Print("EXIT ", symbol, " Reason: ", reason);
         return g_Trade.PositionClose(ticket);
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 17: CLOSE POSITION BY TICKET                               |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket, string reason)
{
   if(PositionSelectByTicket(ticket))
   {
      string symbol = PositionGetString(POSITION_SYMBOL);
      Print("EXIT ", symbol, " Reason: ", reason);
      return g_Trade.PositionClose(ticket);
   }
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 18: CLOSE ALL POSITIONS                                    |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   int total = PositionsTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      Print("EXIT ALL ", symbol, " Reason: ", reason);
      g_Trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| MODULE 19: CHECK EQUITY TP/SL                                     |
//+------------------------------------------------------------------+
bool CheckEquityTPSL()
{
   if(!UseEquityTP && !UseEquitySL)
      return false;
   
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double deltaPercent = 100.0 * (currentEquity - g_StartEquity) / g_StartEquity;
   
   if(UseEquityTP && deltaPercent >= EquityTP_Percent)
   {
      Print("=== EQUITY TP HIT === Delta: ", deltaPercent, "% Target: ", EquityTP_Percent, "%");
      CloseAllPositions("Equity TP Hit");
      g_StartEquity = currentEquity; // Рестартирай цикъла
      return true;
   }
   
   if(UseEquitySL && deltaPercent <= -EquitySL_Percent)
   {
      Print("=== EQUITY SL HIT === Delta: ", deltaPercent, "% Target: -", EquitySL_Percent, "%");
      CloseAllPositions("Equity SL Hit");
      g_StartEquity = currentEquity; // Рестартирай цикъла
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| MODULE 20: CALCULATE TOTAL RISK                                   |
//+------------------------------------------------------------------+
double CalculateTotalRisk()
{
   double totalRisk = 0;
   int total = PositionsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      string symbol = PositionGetString(POSITION_SYMBOL);
      
      if(sl > 0)
      {
         double slDistance = MathAbs(openPrice - sl);
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         
         double slPoints = slDistance / point;
         double risk = slPoints * tickValue * volume * (point / tickSize);
         totalRisk += risk;
      }
   }
   
   return totalRisk;
}

//+------------------------------------------------------------------+
//| MODULE 21: LOG CURRENCY RANKINGS                                  |
//+------------------------------------------------------------------+
void LogCurrencyRankings()
{
   // Създай масив с индекси и momentum
   int indices[];
   double momValues[];
   ArrayResize(indices, g_CurrencyCount);
   ArrayResize(momValues, g_CurrencyCount);
   
   for(int i = 0; i < g_CurrencyCount; i++)
   {
      indices[i] = i;
      momValues[i] = g_CurrencyMomentumSmoothed[i];
   }
   
   // Сортирай
   for(int i = 0; i < g_CurrencyCount - 1; i++)
   {
      for(int j = i + 1; j < g_CurrencyCount; j++)
      {
         if(momValues[j] > momValues[i])
         {
            double tm = momValues[i]; momValues[i] = momValues[j]; momValues[j] = tm;
            int ti = indices[i]; indices[i] = indices[j]; indices[j] = ti;
         }
      }
   }
   
   // Лог
   Print("=== CURRENCY STRENGTH RANKING ===");
   for(int i = 0; i < g_CurrencyCount; i++)
   {
      Print(i+1, ". ", g_Currencies[indices[i]], 
            " Momentum: ", DoubleToString(momValues[i], 6),
            " StrengthS: ", DoubleToString(g_CurrencyStrengthShort[indices[i]], 6),
            " StrengthL: ", DoubleToString(g_CurrencyStrengthLong[indices[i]], 6));
   }
   Print("================================");
}

//+------------------------------------------------------------------+
