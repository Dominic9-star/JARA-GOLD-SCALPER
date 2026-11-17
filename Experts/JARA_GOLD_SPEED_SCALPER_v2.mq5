#property strict
#property version "2.00"

#include <Trade/Trade.mqh>
CTrade trade;

// Main settings
input string GoldSymbolPrefix = "XAUUSD";
input double Lots = 0.01;
input int StopLossPoints = 80;
input double ProfitTargetMoney = 0.50;
input int MaxSpreadPoints = 50;
input int MaxHoldingSeconds = 30;
input int CooldownSeconds = 10;
input int MaxTradesPerDay = 30;
input double DailyLossLimit = 2.0;

// Entry indicators
input int FastEMA = 5;
input int SlowEMA = 13;
input int RSIPeriod = 7;

input long MagicNumber = 16112026;

int fastHandle = INVALID_HANDLE;
int slowHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;

datetime lastTrade = 0;
int tradesToday = 0;
int currentDayKey = 0;
double dayStartEquity = 0;
bool dailyLossLocked = false;

// Identify the current broker-server day
int GetDayKey()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return t.year * 1000 + t.day_of_year;
}

// Reset daily limits when a new day begins
void ResetDailyStats()
{
   int newKey = GetDayKey();

   if(newKey != currentDayKey)
   {
      currentDayKey = newKey;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      tradesToday = 0;
      dailyLossLocked = false;

      Print("JARA: New trading day. Daily limits reset.");
   }
}

// Check whether this EA already has an open position
bool HasEAPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }

   return false;
}

// Include recorded deal commissions in the profit calculation
double GetNetPositionProfit()
{
   double netProfit =
      PositionGetDouble(POSITION_PROFIT) +
      PositionGetDouble(POSITION_SWAP);

   ulong positionId =
      (ulong)PositionGetInteger(POSITION_IDENTIFIER);

   if(positionId > 0 && HistorySelectByPosition(positionId))
   {
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);

         if(deal > 0)
            netProfit += HistoryDealGetDouble(deal, DEAL_COMMISSION);
      }
   }

   return netProfit;
}

// Close only positions belonging to this EA
void CloseEAPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      trade.PositionClose(ticket);
   }
}

// Monitor profit and maximum holding time
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double netProfit = GetNetPositionProfit();

      datetime opened =
         (datetime)PositionGetInteger(POSITION_TIME);

      bool targetReached = (netProfit >= ProfitTargetMoney);
      bool timeExpired =
         (TimeCurrent() - opened >= MaxHoldingSeconds);

      if(targetReached || timeExpired)
      {
         if(!trade.PositionClose(ticket))
            Print("JARA close failed: ", trade.ResultRetcode(),
                  " ", trade.ResultRetcodeDescription());
      }
   }
}

int OnInit()
{
   if(StringFind(_Symbol, GoldSymbolPrefix) != 0)
   {
      Print("JARA: Attach this EA to an XAUUSD chart.");
      return INIT_FAILED;
   }

   if(Lots <= 0 || StopLossPoints <= 0 ||
      ProfitTargetMoney <= 0 || MaxHoldingSeconds <= 0 ||
      DailyLossLimit <= 0)
      return INIT_PARAMETERS_INCORRECT;

   fastHandle = iMA(_Symbol, PERIOD_M1, FastEMA, 0,
                    MODE_EMA, PRICE_CLOSE);

   slowHandle = iMA(_Symbol, PERIOD_M1, SlowEMA, 0,
                    MODE_EMA, PRICE_CLOSE);

   rsiHandle = iRSI(_Symbol, PERIOD_M1, RSIPeriod,
                    PRICE_CLOSE);

   if(fastHandle == INVALID_HANDLE ||
      slowHandle == INVALID_HANDLE ||
      rsiHandle == INVALID_HANDLE)
   {
      Print("JARA: Indicator initialization failed.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((ulong)MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFillingBySymbol(_Symbol);

   currentDayKey = GetDayKey();
   dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   Print("JARA GOLD SCALPER v2 initialized.");

   return INIT_SUCCEEDED;
}

void OnTick()
{
   ResetDailyStats();

   // Manage open trades before checking for new entries
   ManagePositions();

   // Daily account-equity loss protection
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!dailyLossLocked &&
      equity <= dayStartEquity *
      (1.0 - DailyLossLimit / 100.0))
   {
      dailyLossLocked = true;
      CloseEAPositions();

      Print("JARA: Daily loss limit reached. Trading locked.");
      return;
   }

   if(dailyLossLocked) return;
   if(tradesToday >= MaxTradesPerDay) return;

   if(TimeCurrent() - lastTrade < CooldownSeconds)
      return;

   // One JARA position at a time
   if(HasEAPosition()) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0 || bid <= 0) return;

   double spread = (ask - bid) / _Point;
   if(spread > MaxSpreadPoints) return;

   double fast[], slow[], rsi[];

   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(rsi, true);

   // Use the last completed M1 candle
   if(CopyBuffer(fastHandle, 0, 1, 1, fast) < 1) return;
   if(CopyBuffer(slowHandle, 0, 1, 1, slow) < 1) return;
   if(CopyBuffer(rsiHandle, 0, 1, 1, rsi) < 1) return;

   int brokerStopLevel =
      (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   int actualSLPoints =
      (int)MathMax(StopLossPoints, brokerStopLevel + 2);

   double sl = 0;
   bool submitted = false;

   // BUY signal
   if(fast[0] > slow[0] &&
      rsi[0] >= 52 && rsi[0] <= 75)
   {
      sl = NormalizeDouble(
         ask - actualSLPoints * _Point, _Digits);

      submitted = trade.Buy(Lots, _Symbol, 0, sl, 0);
   }

   // SELL signal
   else if(fast[0] < slow[0] &&
           rsi[0] >= 25 && rsi[0] <= 48)
   {
      sl = NormalizeDouble(
         bid + actualSLPoints * _Point, _Digits);

      submitted = trade.Sell(Lots, _Symbol, 0, sl, 0);
   }

   if(submitted &&
      (trade.ResultRetcode() == TRADE_RETCODE_DONE ||
       trade.ResultRetcode() == TRADE_RETCODE_PLACED ||
       trade.ResultRetcode() == TRADE_RETCODE_DONE_PARTIAL))
   {
      lastTrade = TimeCurrent();
      tradesToday++;

      Print("JARA: Trade opened. Trades today: ", tradesToday);
   }
   else if(submitted)
   {
      Print("JARA order result: ",
            trade.ResultRetcodeDescription());
   }
}

void OnDeinit(const int reason)
{
   if(fastHandle != INVALID_HANDLE)
      IndicatorRelease(fastHandle);

   if(slowHandle != INVALID_HANDLE)
      IndicatorRelease(slowHandle);

   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
}
