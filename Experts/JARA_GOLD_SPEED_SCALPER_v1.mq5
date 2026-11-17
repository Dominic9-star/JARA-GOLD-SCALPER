
#property strict
#property version "1.00"

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

int fastHandle, slowHandle, rsiHandle;
datetime lastTrade = 0;
datetime dayStart = 0;
double startEquity = 0;
int tradesToday = 0;

int OnInit()
{
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

   dayStart = TimeCurrent();
   startEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   return INIT_SUCCEEDED;
}

bool SessionAllowed()
{
   MqlDateTime t;
   TimeToStruct(TimeGMT(), t);

   int hour = t.hour;

   // Approximate UTC windows. Refine for DST before deployment.
   bool london = (hour >= 8 && hour < 16);
   bool newYork = (hour >= 13 && hour < 21);

   return london || newYork;
}

void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
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

   if(!SessionAllowed()) return;

   if(AccountInfoDouble(ACCOUNT_EQUITY) <=
      startEquity * (1.0 - DailyLossLimit/100.0))
      return;

   if(tradesToday >= MaxTradesPerDay) return;

   if(TimeCurrent() - lastTrade < CooldownSeconds)
      return;

   if(PositionsTotal() > 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double spread = (ask-bid)/_Point;
   if(spread > MaxSpreadPoints) return;

   double fast[], slow[], rsi[];

   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(fastHandle,0,0,1,fast) < 1) return;
   if(CopyBuffer(slowHandle,0,0,1,slow) < 1) return;
   if(CopyBuffer(rsiHandle,0,0,1,rsi) < 1) return;

   double sl, tp;

   if(fast[0] > slow[0] &&
      rsi[0] >= 52 && rsi[0] <= 75)
   {
      sl = ask - StopLossPoints*_Point;
      tp = ask + TakeProfitPoints*_Point;

      if(trade.Buy(Lots,_Symbol,0,sl,tp))
      {
         lastTrade = TimeCurrent();
         tradesToday++;
      }
   }

   else if(fast[0] < slow[0] &&
           rsi[0] >= 25 && rsi[0] <= 48)
   {
      sl = bid + StopLossPoints*_Point;
      tp = bid - TakeProfitPoints*_Point;

      if(trade.Sell(Lots,_Symbol,0,sl,tp))
      {
         lastTrade = TimeCurrent();
         tradesToday++;
      }
   }
}

void OnDeinit(const int reason)
{
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
   IndicatorRelease(rsiHandle);
}
