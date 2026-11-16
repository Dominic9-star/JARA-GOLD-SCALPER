#property strict
#property version "1.10"

#include <Trade/Trade.mqh>
CTrade trade;

input double Lots = 0.01;
input int StopLossPoints = 80;
input int TakeProfitPoints = 25;
input int MaxSpreadPoints = 50;
input int MaxHoldingSeconds = 30;
input int CooldownSeconds = 10;
input int MaxTradesPerDay = 30;
input double DailyLossLimit = 2.0;

input int FastEMA = 5;
input int SlowEMA = 13;
input int RSIPeriod = 7;

input long MagicNumber = 16112026;

int fastHandle = INVALID_HANDLE;
int slowHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;

datetime lastTrade = 0;
int tradesToday = 0;
int currentDay = -1;
double dayStartEquity = 0;
bool dailyLossReached = false;

void ResetDailyLimits()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   if(now.day_of_year != currentDay)
   {
      currentDay = now.day_of_year;
      tradesToday = 0;
      dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      dailyLossReached = false;
   }
}

int OnInit()
{
   if(Lots <= 0 || StopLossPoints <= 0 ||
      TakeProfitPoints <= 0 || FastEMA >= SlowEMA)
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
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);

   ResetDailyLimits();

   return INIT_SUCCEEDED;
}

bool SessionAllowed()
{
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);

   return (t.hour >= 8 && t.hour < 16) ||
          (t.hour >= 13 && t.hour < 21);
}

 bool HasOurPosition()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }

   return false;
}

void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      datetime opened =
         (datetime)PositionGetInteger(POSITION_TIME);

      if(TimeCurrent() - opened >= MaxHoldingSeconds)
         trade.PositionClose(ticket);
   }
}

void OnTick()
{
   ManagePositions();
   ResetDailyLimits();

   if(dailyLossReached) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(dayStartEquity > 0 &&
      equity <= dayStartEquity * (1.0 - DailyLossLimit/100.0))
   {
      dailyLossReached = true;
      return;
   }

   if(!SessionAllowed()) return;
   if(tradesToday >= MaxTradesPerDay) return;
   if(TimeCurrent() - lastTrade < CooldownSeconds) return;
   if(HasOurPosition()) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0 || bid <= 0) return;

   double spread = (ask-bid)/_Point;
   if(spread > MaxSpreadPoints) return;

   double fast[], slow[], rsi[];

   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(fastHandle,0,1,1,fast) != 1) return;
   if(CopyBuffer(slowHandle,0,1,1,slow) != 1) return;
   if(CopyBuffer(rsiHandle,0,1,1,rsi) != 1) return;

   double sl, tp;

   if(fast[0] > slow[0] && rsi[0] >= 52 && rsi[0] <= 75)
   {
      sl = NormalizeDouble(ask - StopLossPoints*_Point,_Digits);
      tp = NormalizeDouble(ask + TakeProfitPoints*_Point,_Digits);

      if(trade.Buy(Lots,_Symbol,0,sl,tp))
      {
         lastTrade = TimeCurrent();
         tradesToday++;
      }
   }
   else if(fast[0] < slow[0] && rsi[0] >= 25 && rsi[0] <= 48)
   {
      sl = NormalizeDouble(bid + StopLossPoints*_Point,_Digits);
      tp = NormalizeDouble(bid - TakeProfitPoints*_Point,_Digits);

      if(trade.Sell(Lots,_Symbol,0,sl,tp))
      {
         lastTrade = TimeCurrent();
         tradesToday++;
      }
   }
}

void OnDeinit(const int reason)
{
   if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
   if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
}













