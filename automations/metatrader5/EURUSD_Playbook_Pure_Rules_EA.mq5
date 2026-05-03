//+------------------------------------------------------------------+
//| EURUSD Playbook Pure Rules EA                                    |
//| Mechanical EA from the user's playbook with toggleable range logic |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Pure EURUSD playbook EA: 4H FVG/range setups, 15m confirmation, 3-candle fractal stop."

#include <Trade/Trade.mqh>

struct TradePlan
{
   double entry;
   double stop;
   double target;
   double riskDistance;
   double lots;
};

input bool     EnableTrading = false;
input string   TradeSymbol = "EURUSD";
input long     MagicNumber = 26042502;
input double   RiskPerTradePct = 1.0;
input double   RR = 2.0;
input bool     AllowLong = true;
input bool     AllowShort = true;
input bool     RequireM15 = true;
input datetime BacktestStart = D'2024.01.01 00:00';
input datetime BacktestEnd = D'2099.12.31 23:59';

input int      SwingLen = 1;                 // 1 = 3-candle fractal.
input double   FractalStopBufferPips = 2.0;
input bool     UseNoEntryAfterHour = true;
input int      NoEntryAfterHour = 22;

input bool     UseBosConfirmation = true;
input bool     UseNewFvgConfirmation = true;
input bool     UseIfvgConfirmation = true;
input bool     AllowOneReEntry = true;
input bool     RequireNewConfirmationForReEntry = true;
input bool     UseFtaRrFilter = true;
input double   MinRrToFta = 2.0;
input int      FtaLookbackBars = 96;
input bool     UseLimitWhenFtaRrTooLow = true;
input double   LimitEntryBufferPips = 0.0;
input bool     CancelLimitWhenFtaReached = true;

input bool     UseRangeLogic = true;
input int      RangeLookbackBars = 96;
input int      RangeMinTouches = 2;
input double   RangeBoundaryTolerancePips = 3.0;
input double   RangeMiddleBlockPct = 35.0;
input double   RangeStopBufferPips = 2.0;
input bool     UseRangeLimitIfStopLarge = true;
input double   MaxRangeStopPipsForMarket = 15.0;
input bool     DisableRangeWhenH4FvgActive = true;

CTrade trade;

datetime lastM15BarTime = 0;
string lastSignal = "None";

double activeBullLow = 0.0;
double activeBullHigh = 0.0;
double activeBearLow = 0.0;
double activeBearHigh = 0.0;
bool hasActiveBullZone = false;
bool hasActiveBearZone = false;
bool bullZoneTested = false;
bool bearZoneTested = false;
bool bullZoneInvalidated = false;
bool bearZoneInvalidated = false;
datetime activeBullH4Time = 0;
datetime activeBearH4Time = 0;

bool bullIdeaUsed = false;
bool bearIdeaUsed = false;
bool bullWaitingReEntry = false;
bool bearWaitingReEntry = false;
bool bullReEntryUsed = false;
bool bearReEntryUsed = false;
ulong lastProcessedCloseDeal = 0;

ulong pendingTicket = 0;
bool pendingIsLong = false;
bool pendingIsReEntry = false;
bool pendingIsRange = false;
double pendingFtaPrice = 0.0;
datetime pendingSituationTime = 0;
datetime pendingOrderDay = 0;

bool rangeActive = false;
double rangeUpper = 0.0;
double rangeLower = 0.0;
double rangeSweptHigh = 0.0;
double rangeSweptLow = 0.0;
bool rangeLongReady = false;
bool rangeShortReady = false;
bool rangeLongIdeaUsed = false;
bool rangeShortIdeaUsed = false;
bool rangeLongWaitingReEntry = false;
bool rangeShortWaitingReEntry = false;
bool rangeLongReEntryUsed = false;
bool rangeShortReEntryUsed = false;
datetime rangeSituationTime = 0;

double lastBullFvgLow15 = 0.0;
double lastBullFvgHigh15 = 0.0;
double lastBearFvgLow15 = 0.0;
double lastBearFvgHigh15 = 0.0;
bool hasLastBullFvg15 = false;
bool hasLastBearFvg15 = false;

double lastFractalHigh = 0.0;
double lastFractalLow = 0.0;
bool hasLastFractalHigh = false;
bool hasLastFractalLow = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   if(_Symbol != TradeSymbol)
      Print("Warning: EA is configured for ", TradeSymbol, " but chart symbol is ", _Symbol);

   InitializeLastProcessedCloseDeal();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateReEntryState();
   ManagePendingLimit();
   UpdatePanel();

   if(!IsNewM15Bar())
      return;

   EvaluateOnNewBar();
}

//+------------------------------------------------------------------+
void EvaluateOnNewBar()
{
   if(_Symbol != TradeSymbol)
      return;
   if(RequireM15 && Period() != PERIOD_M15)
      return;

   MqlRates m15[];
   MqlRates h4[];
   ArraySetAsSeries(m15, true);
   ArraySetAsSeries(h4, true);

   int needBars = MathMax(MathMax(MathMax(100, FtaLookbackBars + SwingLen * 2 + 10), RangeLookbackBars + SwingLen * 2 + 10), SwingLen * 2 + 10);
   if(CopyRates(TradeSymbol, PERIOD_M15, 0, needBars, m15) < needBars)
      return;
   if(CopyRates(TradeSymbol, PERIOD_H4, 0, 10, h4) < 5)
      return;

   UpdateH4Zones(h4);
   UpdateM15Context(m15);
   UpdateRangeContext(m15, h4);

   if(!CanOpenNewTrade())
      return;

   bool bosUp = IsBosUp(m15);
   bool bosDown = IsBosDown(m15);
   bool newBullFvg = IsNewBullFvg15(m15);
   bool newBearFvg = IsNewBearFvg15(m15);
   bool ifvgUp = IsIfvgUp(m15);
   bool ifvgDown = IsIfvgDown(m15);

   bool longConfirmation = (UseBosConfirmation && bosUp) || (UseNewFvgConfirmation && newBullFvg) || (UseIfvgConfirmation && ifvgUp);
   bool shortConfirmation = (UseBosConfirmation && bosDown) || (UseNewFvgConfirmation && newBearFvg) || (UseIfvgConfirmation && ifvgDown);

   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);

   TradePlan longPlan;
   TradePlan shortPlan;
   TradePlan rangeLongPlan;
   TradePlan rangeShortPlan;
   bool longPlanOk = BuildLongPlan(ask, longPlan);
   bool shortPlanOk = BuildShortPlan(bid, shortPlan);
   bool rangeLongPlanOk = BuildRangeLongPlan(ask, rangeLongPlan);
   bool rangeShortPlanOk = BuildRangeShortPlan(bid, rangeShortPlan);

   bool longFirstEntry = AllowLong && !bullIdeaUsed && hasActiveBullZone && bullZoneTested && !bullZoneInvalidated && longConfirmation && longPlanOk;
   bool shortFirstEntry = AllowShort && !bearIdeaUsed && hasActiveBearZone && bearZoneTested && !bearZoneInvalidated && shortConfirmation && shortPlanOk;
   bool longReEntry = AllowLong && AllowOneReEntry && bullIdeaUsed && bullWaitingReEntry && !bullReEntryUsed && hasActiveBullZone && bullZoneTested && !bullZoneInvalidated && (!RequireNewConfirmationForReEntry || longConfirmation) && longPlanOk;
   bool shortReEntry = AllowShort && AllowOneReEntry && bearIdeaUsed && bearWaitingReEntry && !bearReEntryUsed && hasActiveBearZone && bearZoneTested && !bearZoneInvalidated && (!RequireNewConfirmationForReEntry || shortConfirmation) && shortPlanOk;
   bool rangeLongFirstEntry = UseRangeLogic && AllowLong && !rangeLongIdeaUsed && rangeActive && rangeLongReady && longConfirmation && rangeLongPlanOk;
   bool rangeShortFirstEntry = UseRangeLogic && AllowShort && !rangeShortIdeaUsed && rangeActive && rangeShortReady && shortConfirmation && rangeShortPlanOk;
   bool rangeLongReEntry = UseRangeLogic && AllowLong && AllowOneReEntry && rangeLongIdeaUsed && rangeLongWaitingReEntry && !rangeLongReEntryUsed && rangeActive && rangeLongReady && (!RequireNewConfirmationForReEntry || longConfirmation) && rangeLongPlanOk;
   bool rangeShortReEntry = UseRangeLogic && AllowShort && AllowOneReEntry && rangeShortIdeaUsed && rangeShortWaitingReEntry && !rangeShortReEntryUsed && rangeActive && rangeShortReady && (!RequireNewConfirmationForReEntry || shortConfirmation) && rangeShortPlanOk;

   if(longFirstEntry)
   {
      lastSignal = "Long: 4H FVG tested + 15m confirmation";
      if(HandleEntry(ORDER_TYPE_BUY, longPlan, false, false, m15))
      {
         bullIdeaUsed = true;
         bullWaitingReEntry = false;
      }
      return;
   }

   if(shortFirstEntry)
   {
      lastSignal = "Short: 4H FVG tested + 15m confirmation";
      if(HandleEntry(ORDER_TYPE_SELL, shortPlan, false, false, m15))
      {
         bearIdeaUsed = true;
         bearWaitingReEntry = false;
      }
      return;
   }

   if(longReEntry)
   {
      lastSignal = "Long re-entry: same 4H FVG + new 15m confirmation";
      if(HandleEntry(ORDER_TYPE_BUY, longPlan, true, false, m15))
      {
         bullReEntryUsed = true;
         bullWaitingReEntry = false;
      }
      return;
   }

   if(shortReEntry)
   {
      lastSignal = "Short re-entry: same 4H FVG + new 15m confirmation";
      if(HandleEntry(ORDER_TYPE_SELL, shortPlan, true, false, m15))
      {
         bearReEntryUsed = true;
         bearWaitingReEntry = false;
      }
      return;
   }

   if(rangeLongFirstEntry)
   {
      lastSignal = "Range long: lower boundary sweep-return + 15m confirmation";
      if(HandleEntry(ORDER_TYPE_BUY, rangeLongPlan, false, true, m15))
      {
         rangeLongIdeaUsed = true;
         rangeLongWaitingReEntry = false;
      }
      return;
   }

   if(rangeShortFirstEntry)
   {
      lastSignal = "Range short: upper boundary sweep-return + 15m confirmation";
      if(HandleEntry(ORDER_TYPE_SELL, rangeShortPlan, false, true, m15))
      {
         rangeShortIdeaUsed = true;
         rangeShortWaitingReEntry = false;
      }
      return;
   }

   if(rangeLongReEntry)
   {
      lastSignal = "Range long re-entry: same range + new 15m confirmation";
      if(HandleEntry(ORDER_TYPE_BUY, rangeLongPlan, true, true, m15))
      {
         rangeLongReEntryUsed = true;
         rangeLongWaitingReEntry = false;
      }
      return;
   }

   if(rangeShortReEntry)
   {
      lastSignal = "Range short re-entry: same range + new 15m confirmation";
      if(HandleEntry(ORDER_TYPE_SELL, rangeShortPlan, true, true, m15))
      {
         rangeShortReEntryUsed = true;
         rangeShortWaitingReEntry = false;
      }
   }
}

//+------------------------------------------------------------------+
void UpdateH4Zones(const MqlRates &h4[])
{
   bool bullFvg = h4[1].low > h4[3].high;
   bool bearFvg = h4[1].high < h4[3].low;

   if(bullFvg)
   {
      double newBullLow = h4[3].high;
      double newBullHigh = h4[1].low;
      if(!hasActiveBullZone || activeBullH4Time != h4[1].time || activeBullLow != newBullLow || activeBullHigh != newBullHigh)
      {
         activeBullLow = newBullLow;
         activeBullHigh = newBullHigh;
         activeBullH4Time = h4[1].time;
         ResetBullIdea();
         hasActiveBullZone = true;
      }
   }

   if(bearFvg)
   {
      double newBearLow = h4[1].high;
      double newBearHigh = h4[3].low;
      if(!hasActiveBearZone || activeBearH4Time != h4[1].time || activeBearLow != newBearLow || activeBearHigh != newBearHigh)
      {
         activeBearLow = newBearLow;
         activeBearHigh = newBearHigh;
         activeBearH4Time = h4[1].time;
         ResetBearIdea();
         hasActiveBearZone = true;
      }
   }

   // Playbook invalidation: after testing a 4H FVG, a closed H4 candle beyond the zone cancels the plan.
   if(hasActiveBullZone && bullZoneTested && h4[1].close < activeBullLow)
      bullZoneInvalidated = true;
   if(hasActiveBearZone && bearZoneTested && h4[1].close > activeBearHigh)
      bearZoneInvalidated = true;
}

void ResetBullIdea()
{
   bullZoneTested = false;
   bullZoneInvalidated = false;
   bullIdeaUsed = false;
   bullWaitingReEntry = false;
   bullReEntryUsed = false;
}

void ResetBearIdea()
{
   bearZoneTested = false;
   bearZoneInvalidated = false;
   bearIdeaUsed = false;
   bearWaitingReEntry = false;
   bearReEntryUsed = false;
}

//+------------------------------------------------------------------+
void UpdateM15Context(const MqlRates &m15[])
{
   if(hasActiveBullZone && m15[1].low <= activeBullHigh && m15[1].high >= activeBullLow)
      bullZoneTested = true;
   if(hasActiveBearZone && m15[1].high >= activeBearLow && m15[1].low <= activeBearHigh)
      bearZoneTested = true;

   if(IsNewBullFvg15(m15))
   {
      lastBullFvgLow15 = m15[3].high;
      lastBullFvgHigh15 = m15[1].low;
      hasLastBullFvg15 = true;
   }

   if(IsNewBearFvg15(m15))
   {
      lastBearFvgLow15 = m15[1].high;
      lastBearFvgHigh15 = m15[3].low;
      hasLastBearFvg15 = true;
   }

   UpdateFractals(m15);
}

void UpdateRangeContext(const MqlRates &m15[], const MqlRates &h4[])
{
   if(!UseRangeLogic)
   {
      rangeActive = false;
      return;
   }

   if(DisableRangeWhenH4FvgActive && (h4[1].low > h4[3].high || h4[1].high < h4[3].low))
   {
      rangeActive = false;
      return;
   }

   double upper = 0.0;
   double lower = 0.0;
   int upperTouches = 0;
   int lowerTouches = 0;
   if(!FindRangeBoundaries(m15, upper, lower, upperTouches, lowerTouches))
   {
      rangeActive = false;
      return;
   }

   bool newRange = !rangeActive || MathAbs(upper - rangeUpper) > RangeBoundaryTolerancePips * PipSize() || MathAbs(lower - rangeLower) > RangeBoundaryTolerancePips * PipSize();
   if(newRange)
   {
      rangeUpper = upper;
      rangeLower = lower;
      rangeSituationTime = m15[1].time;
      rangeLongIdeaUsed = false;
      rangeShortIdeaUsed = false;
      rangeLongWaitingReEntry = false;
      rangeShortWaitingReEntry = false;
      rangeLongReEntryUsed = false;
      rangeShortReEntryUsed = false;
   }

   rangeActive = true;
   double tolerance = RangeBoundaryTolerancePips * PipSize();
   bool sweptLower = m15[2].low < rangeLower - tolerance && m15[1].close > rangeLower;
   bool sweptUpper = m15[2].high > rangeUpper + tolerance && m15[1].close < rangeUpper;

   if(sweptLower)
   {
      rangeLongReady = true;
      rangeSweptLow = m15[2].low;
   }
   if(sweptUpper)
   {
      rangeShortReady = true;
      rangeSweptHigh = m15[2].high;
   }

   if(IsPriceInRangeMiddle(m15[1].close))
   {
      rangeLongReady = false;
      rangeShortReady = false;
   }
}

bool FindRangeBoundaries(const MqlRates &m15[], double &upper, double &lower, int &upperTouches, int &lowerTouches)
{
   int maxIndex = (int)MathMin((double)RangeLookbackBars, (double)(ArraySize(m15) - SwingLen - 1));
   if(maxIndex <= SwingLen + 2)
      return false;

   bool hasUpper = false;
   bool hasLower = false;
   double highestFractal = 0.0;
   double lowestFractal = 0.0;

   for(int i = SwingLen + 1; i <= maxIndex; i++)
   {
      if(IsFractalHighAt(m15, i))
      {
         if(!hasUpper || m15[i].high > highestFractal)
         {
            highestFractal = m15[i].high;
            hasUpper = true;
         }
      }
      if(IsFractalLowAt(m15, i))
      {
         if(!hasLower || m15[i].low < lowestFractal)
         {
            lowestFractal = m15[i].low;
            hasLower = true;
         }
      }
   }

   if(!hasUpper || !hasLower || highestFractal <= lowestFractal)
      return false;

   double tolerance = RangeBoundaryTolerancePips * PipSize();
   upperTouches = 0;
   lowerTouches = 0;
   for(int i = 1; i <= maxIndex; i++)
   {
      if(MathAbs(m15[i].high - highestFractal) <= tolerance)
         upperTouches++;
      if(MathAbs(m15[i].low - lowestFractal) <= tolerance)
         lowerTouches++;
   }

   if(upperTouches < RangeMinTouches || lowerTouches < RangeMinTouches)
      return false;

   upper = highestFractal;
   lower = lowestFractal;
   return true;
}

bool IsPriceInRangeMiddle(double price)
{
   if(!rangeActive || rangeUpper <= rangeLower)
      return false;
   double height = rangeUpper - rangeLower;
   double lowerMid = rangeLower + height * (RangeMiddleBlockPct / 100.0);
   double upperMid = rangeUpper - height * (RangeMiddleBlockPct / 100.0);
   return price > lowerMid && price < upperMid;
}

//+------------------------------------------------------------------+
void UpdateFractals(const MqlRates &m15[])
{
   int pivotIndex = SwingLen + 1;
   bool fractalHigh = true;
   bool fractalLow = true;

   for(int i = pivotIndex - SwingLen; i <= pivotIndex + SwingLen; i++)
   {
      if(i == pivotIndex)
         continue;
      if(m15[pivotIndex].high <= m15[i].high)
         fractalHigh = false;
      if(m15[pivotIndex].low >= m15[i].low)
         fractalLow = false;
   }

   if(fractalHigh)
   {
      lastFractalHigh = m15[pivotIndex].high;
      hasLastFractalHigh = true;
   }
   if(fractalLow)
   {
      lastFractalLow = m15[pivotIndex].low;
      hasLastFractalLow = true;
   }
}

//+------------------------------------------------------------------+
bool IsNewBullFvg15(const MqlRates &m15[])
{
   return m15[1].low > m15[3].high;
}

bool IsNewBearFvg15(const MqlRates &m15[])
{
   return m15[1].high < m15[3].low;
}

bool IsIfvgUp(const MqlRates &m15[])
{
   return hasLastBearFvg15 && m15[1].close > lastBearFvgHigh15 && m15[2].close <= lastBearFvgHigh15;
}

bool IsIfvgDown(const MqlRates &m15[])
{
   return hasLastBullFvg15 && m15[1].close < lastBullFvgLow15 && m15[2].close >= lastBullFvgLow15;
}

bool IsBosUp(const MqlRates &m15[])
{
   return hasLastFractalHigh && m15[1].close > lastFractalHigh && m15[2].close <= lastFractalHigh;
}

bool IsBosDown(const MqlRates &m15[])
{
   return hasLastFractalLow && m15[1].close < lastFractalLow && m15[2].close >= lastFractalLow;
}

//+------------------------------------------------------------------+
bool BuildLongPlan(double entry, TradePlan &plan)
{
   if(!hasLastFractalLow || lastFractalLow >= entry)
      return false;

   double buffer = FractalStopBufferPips * PipSize();
   double stop = NormalizePrice(lastFractalLow - buffer);
   double riskDistance = entry - stop;
   if(riskDistance <= SymbolInfoDouble(TradeSymbol, SYMBOL_POINT))
      return false;

   double target = NormalizePrice(entry + riskDistance * RR);
   double lots = CalculateLots(riskDistance);
   if(lots <= 0.0)
      return false;

   plan.entry = entry;
   plan.stop = stop;
   plan.target = target;
   plan.riskDistance = riskDistance;
   plan.lots = lots;
   return true;
}

bool BuildShortPlan(double entry, TradePlan &plan)
{
   if(!hasLastFractalHigh || lastFractalHigh <= entry)
      return false;

   double buffer = FractalStopBufferPips * PipSize();
   double stop = NormalizePrice(lastFractalHigh + buffer);
   double riskDistance = stop - entry;
   if(riskDistance <= SymbolInfoDouble(TradeSymbol, SYMBOL_POINT))
      return false;

   double target = NormalizePrice(entry - riskDistance * RR);
   double lots = CalculateLots(riskDistance);
   if(lots <= 0.0)
      return false;

   plan.entry = entry;
   plan.stop = stop;
   plan.target = target;
   plan.riskDistance = riskDistance;
   plan.lots = lots;
   return true;
}

bool BuildRangeLongPlan(double entry, TradePlan &plan)
{
   if(!rangeActive || !rangeLongReady || rangeSweptLow <= 0.0 || rangeSweptLow >= entry)
      return false;

   double stop = NormalizePrice(rangeSweptLow - RangeStopBufferPips * PipSize());
   double riskDistance = entry - stop;
   if(riskDistance <= SymbolInfoDouble(TradeSymbol, SYMBOL_POINT))
      return false;

   if(UseRangeLimitIfStopLarge && riskDistance / PipSize() > MaxRangeStopPipsForMarket)
   {
      // The FTA/limit module will improve entry if the opposite boundary is too close for market.
   }

   double target = NormalizePrice(entry + riskDistance * RR);
   double lots = CalculateLots(riskDistance);
   if(lots <= 0.0)
      return false;

   plan.entry = entry;
   plan.stop = stop;
   plan.target = target;
   plan.riskDistance = riskDistance;
   plan.lots = lots;
   return true;
}

bool BuildRangeShortPlan(double entry, TradePlan &plan)
{
   if(!rangeActive || !rangeShortReady || rangeSweptHigh <= 0.0 || rangeSweptHigh <= entry)
      return false;

   double stop = NormalizePrice(rangeSweptHigh + RangeStopBufferPips * PipSize());
   double riskDistance = stop - entry;
   if(riskDistance <= SymbolInfoDouble(TradeSymbol, SYMBOL_POINT))
      return false;

   if(UseRangeLimitIfStopLarge && riskDistance / PipSize() > MaxRangeStopPipsForMarket)
   {
      // The FTA/limit module will improve entry if the opposite boundary is too close for market.
   }

   double target = NormalizePrice(entry - riskDistance * RR);
   double lots = CalculateLots(riskDistance);
   if(lots <= 0.0)
      return false;

   plan.entry = entry;
   plan.stop = stop;
   plan.target = target;
   plan.riskDistance = riskDistance;
   plan.lots = lots;
   return true;
}

//+------------------------------------------------------------------+
bool ExecutePlan(ENUM_ORDER_TYPE orderType, const TradePlan &plan, bool isReEntry, bool isRange)
{
   string side = orderType == ORDER_TYPE_BUY ? "BUY" : "SELL";
   Print(side, " signal: lots=", DoubleToString(plan.lots, 2), " entry=", DoubleToString(plan.entry, _Digits), " sl=", DoubleToString(plan.stop, _Digits), " tp=", DoubleToString(plan.target, _Digits));

   if(!EnableTrading)
   {
      Print("EnableTrading=false. Signal logged only, no order sent.");
      return false;
   }

   bool ok = false;
   string comment = isRange ? (isReEntry ? "Pure Range ReEntry" : "Pure Range Entry") : (isReEntry ? "Pure FVG ReEntry" : "Pure FVG Entry");
   if(orderType == ORDER_TYPE_BUY)
      ok = trade.Buy(plan.lots, TradeSymbol, 0.0, plan.stop, plan.target, comment + " Long");
   else
      ok = trade.Sell(plan.lots, TradeSymbol, 0.0, plan.stop, plan.target, comment + " Short");

   if(!ok)
   {
      Print("Order failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }

   return true;
}

bool HandleEntry(ENUM_ORDER_TYPE orderType, const TradePlan &marketPlan, bool isReEntry, bool isRange, const MqlRates &m15[])
{
   bool isLong = orderType == ORDER_TYPE_BUY;
   double fta = 0.0;
   bool hasFta = isLong ? FindNearestLongFta(m15, marketPlan.entry, fta) : FindNearestShortFta(m15, marketPlan.entry, fta);

   if(!UseFtaRrFilter || !hasFta)
      return ExecutePlan(orderType, marketPlan, isReEntry, isRange);

   double rewardToFta = isLong ? fta - marketPlan.entry : marketPlan.entry - fta;
   double rrToFta = marketPlan.riskDistance > 0.0 ? rewardToFta / marketPlan.riskDistance : 0.0;
   bool rangeStopTooLarge = isRange && UseRangeLimitIfStopLarge && marketPlan.riskDistance / PipSize() > MaxRangeStopPipsForMarket;
   if(rrToFta >= MinRrToFta && !rangeStopTooLarge)
   {
      Print("FTA RR OK: rrToFta=", DoubleToString(rrToFta, 2), " fta=", DoubleToString(fta, _Digits));
      return ExecutePlan(orderType, marketPlan, isReEntry, isRange);
   }

   if(!UseLimitWhenFtaRrTooLow)
   {
      Print("Market skipped: RR to FTA too low or range stop too large. rrToFta=", DoubleToString(rrToFta, 2), " fta=", DoubleToString(fta, _Digits));
      return false;
   }

   TradePlan limitPlan;
   if(!BuildLimitPlan(orderType, marketPlan.stop, fta, limitPlan))
   {
      Print("Limit skipped: cannot build valid limit plan for FTA RR. fta=", DoubleToString(fta, _Digits));
      return false;
   }

   return PlaceLimitPlan(orderType, limitPlan, fta, isReEntry, isRange);
}

bool BuildLimitPlan(ENUM_ORDER_TYPE orderType, double stop, double fta, TradePlan &plan)
{
   bool isLong = orderType == ORDER_TYPE_BUY;
   double current = isLong ? SymbolInfoDouble(TradeSymbol, SYMBOL_ASK) : SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
   double rawEntry = (fta + MinRrToFta * stop) / (MinRrToFta + 1.0);
   double buffer = LimitEntryBufferPips * PipSize();
   double entry = NormalizePrice(isLong ? rawEntry - buffer : rawEntry + buffer);

   if(isLong && (entry >= current || entry <= stop))
      return false;
   if(!isLong && (entry <= current || entry >= stop))
      return false;

   double riskDistance = isLong ? entry - stop : stop - entry;
   double rewardToFta = isLong ? fta - entry : entry - fta;
   if(riskDistance <= SymbolInfoDouble(TradeSymbol, SYMBOL_POINT) || rewardToFta <= 0.0)
      return false;
   if(rewardToFta / riskDistance < MinRrToFta)
      return false;

   double target = NormalizePrice(isLong ? entry + riskDistance * RR : entry - riskDistance * RR);
   double lots = CalculateLots(riskDistance);
   if(lots <= 0.0)
      return false;

   plan.entry = entry;
   plan.stop = stop;
   plan.target = target;
   plan.riskDistance = riskDistance;
   plan.lots = lots;
   return true;
}

bool PlaceLimitPlan(ENUM_ORDER_TYPE orderType, const TradePlan &plan, double fta, bool isReEntry, bool isRange)
{
   bool isLong = orderType == ORDER_TYPE_BUY;
   Print((isLong ? "BUY LIMIT" : "SELL LIMIT"), " because RR to FTA is too low: lots=", DoubleToString(plan.lots, 2), " entry=", DoubleToString(plan.entry, _Digits), " sl=", DoubleToString(plan.stop, _Digits), " tp=", DoubleToString(plan.target, _Digits), " fta=", DoubleToString(fta, _Digits));

   if(!EnableTrading)
   {
      Print("EnableTrading=false. Limit signal logged only, no pending order sent.");
      return false;
   }

   bool ok = false;
   if(isLong)
      ok = trade.BuyLimit(plan.lots, plan.entry, TradeSymbol, plan.stop, plan.target, ORDER_TIME_GTC, 0, isRange ? (isReEntry ? "Pure Range Long ReEntry Limit" : "Pure Range Long Limit") : (isReEntry ? "Pure FVG Long ReEntry Limit" : "Pure FVG Long Limit"));
   else
      ok = trade.SellLimit(plan.lots, plan.entry, TradeSymbol, plan.stop, plan.target, ORDER_TIME_GTC, 0, isRange ? (isReEntry ? "Pure Range Short ReEntry Limit" : "Pure Range Short Limit") : (isReEntry ? "Pure FVG Short ReEntry Limit" : "Pure FVG Short Limit"));

   if(!ok)
   {
      Print("Limit order failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }

   pendingTicket = trade.ResultOrder();
   pendingIsLong = isLong;
   pendingIsReEntry = isReEntry;
   pendingIsRange = isRange;
   pendingFtaPrice = fta;
   pendingSituationTime = isRange ? rangeSituationTime : (isLong ? activeBullH4Time : activeBearH4Time);
   pendingOrderDay = DayStart(TimeCurrent());
   return true;
}

//+------------------------------------------------------------------+
bool CanOpenNewTrade()
{
   datetime now = TimeCurrent();
   if(now < BacktestStart || now > BacktestEnd)
      return false;
   if(HasOpenPosition())
      return false;
   if(HasPendingOrder())
      return false;

   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(UseNoEntryAfterHour && dt.hour >= NoEntryAfterHour)
      return false;

   return true;
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == TradeSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

bool HasPendingOrder()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != TradeSymbol || OrderGetInteger(ORDER_MAGIC) != MagicNumber)
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
      {
         pendingTicket = ticket;
         return true;
      }
   }
   pendingTicket = 0;
   return false;
}

bool FindNearestLongFta(const MqlRates &m15[], double entry, double &fta)
{
   bool found = false;
   double nearest = 0.0;
   int maxIndex = (int)MathMin((double)FtaLookbackBars, (double)(ArraySize(m15) - SwingLen - 1));

   for(int i = SwingLen + 1; i <= maxIndex; i++)
   {
      if(!IsFractalHighAt(m15, i))
         continue;
      double level = m15[i].high;
      if(level <= entry)
         continue;
      if(!found || level < nearest)
      {
         nearest = level;
         found = true;
      }
   }

   if(rangeActive && rangeUpper > entry && (!found || rangeUpper < nearest))
   {
      nearest = rangeUpper;
      found = true;
   }

   fta = nearest;
   return found;
}

bool FindNearestShortFta(const MqlRates &m15[], double entry, double &fta)
{
   bool found = false;
   double nearest = 0.0;
   int maxIndex = (int)MathMin((double)FtaLookbackBars, (double)(ArraySize(m15) - SwingLen - 1));

   for(int i = SwingLen + 1; i <= maxIndex; i++)
   {
      if(!IsFractalLowAt(m15, i))
         continue;
      double level = m15[i].low;
      if(level >= entry)
         continue;
      if(!found || level > nearest)
      {
         nearest = level;
         found = true;
      }
   }

   if(rangeActive && rangeLower < entry && (!found || rangeLower > nearest))
   {
      nearest = rangeLower;
      found = true;
   }

   fta = nearest;
   return found;
}

bool IsFractalHighAt(const MqlRates &m15[], int index)
{
   for(int i = index - SwingLen; i <= index + SwingLen; i++)
   {
      if(i == index)
         continue;
      if(m15[index].high <= m15[i].high)
         return false;
   }
   return true;
}

bool IsFractalLowAt(const MqlRates &m15[], int index)
{
   for(int i = index - SwingLen; i <= index + SwingLen; i++)
   {
      if(i == index)
         continue;
      if(m15[index].low >= m15[i].low)
         return false;
   }
   return true;
}

void ManagePendingLimit()
{
   if(pendingTicket == 0 && !HasPendingOrder())
      return;

   bool cancel = false;
   string reason = "";

   if(HasOpenPosition())
   {
      pendingTicket = 0;
      pendingFtaPrice = 0.0;
      pendingSituationTime = 0;
      pendingIsRange = false;
      return;
   }
   else if(CancelLimitWhenFtaReached && pendingFtaPrice > 0.0)
   {
      double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
      if(pendingIsLong && bid >= pendingFtaPrice)
      {
         cancel = true;
         reason = "FTA reached before buy limit fill";
      }
      if(!pendingIsLong && ask <= pendingFtaPrice)
      {
         cancel = true;
         reason = "FTA reached before sell limit fill";
      }
   }

   if(!cancel && pendingOrderDay > 0 && DayStart(TimeCurrent()) > pendingOrderDay)
   {
      cancel = true;
      reason = "pending limit expired on next broker day";
   }

   if(!cancel && pendingIsRange && (!rangeActive || rangeSituationTime != pendingSituationTime))
   {
      cancel = true;
      reason = "range situation invalidated or changed";
   }
   if(!cancel && !pendingIsRange && pendingIsLong && (bullZoneInvalidated || activeBullH4Time != pendingSituationTime))
   {
      cancel = true;
      reason = "long situation invalidated or changed";
   }
   if(!cancel && !pendingIsRange && !pendingIsLong && (bearZoneInvalidated || activeBearH4Time != pendingSituationTime))
   {
      cancel = true;
      reason = "short situation invalidated or changed";
   }

   if(!cancel && UseNoEntryAfterHour)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour >= NoEntryAfterHour)
      {
         cancel = true;
         reason = "entry time expired";
      }
   }

   if(cancel)
      CancelPendingLimit(reason);
}

void CancelPendingLimit(string reason)
{
   if(pendingTicket == 0)
      return;
   Print("Cancel pending limit ", pendingTicket, ": ", reason);
   trade.OrderDelete(pendingTicket);
   pendingTicket = 0;
   pendingIsRange = false;
   pendingFtaPrice = 0.0;
   pendingSituationTime = 0;
   pendingOrderDay = 0;
}

void InitializeLastProcessedCloseDeal()
{
   if(!HistorySelect(0, TimeCurrent()))
      return;

   ulong latest = 0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != TradeSymbol)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      if(deal > latest)
         latest = deal;
   }
   lastProcessedCloseDeal = latest;
}

void UpdateReEntryState()
{
   if(!AllowOneReEntry)
      return;
   if(!HistorySelect(0, TimeCurrent()))
      return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || deal <= lastProcessedCloseDeal)
         continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != TradeSymbol)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber)
         continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;

      long dealType = HistoryDealGetInteger(deal, DEAL_TYPE);
      long reason = HistoryDealGetInteger(deal, DEAL_REASON);
      string comment = HistoryDealGetString(deal, DEAL_COMMENT);
      bool rangeDeal = StringFind(comment, "Range") >= 0;
      bool closedLong = dealType == DEAL_TYPE_SELL;
      bool closedShort = dealType == DEAL_TYPE_BUY;
      bool stopped = reason == DEAL_REASON_SL;

      if(closedLong)
      {
         if(rangeDeal)
         {
            if(stopped && rangeLongIdeaUsed && !rangeLongReEntryUsed && rangeActive)
            {
               rangeLongWaitingReEntry = true;
               lastSignal = "Range long stopped: waiting one re-entry confirmation";
            }
            else
            {
               rangeLongWaitingReEntry = false;
            }
         }
         else if(stopped && bullIdeaUsed && !bullReEntryUsed && !bullZoneInvalidated)
         {
            bullWaitingReEntry = true;
            lastSignal = "Long stopped: waiting one re-entry confirmation";
         }
         else
         {
            bullWaitingReEntry = false;
         }
      }

      if(closedShort)
      {
         if(rangeDeal)
         {
            if(stopped && rangeShortIdeaUsed && !rangeShortReEntryUsed && rangeActive)
            {
               rangeShortWaitingReEntry = true;
               lastSignal = "Range short stopped: waiting one re-entry confirmation";
            }
            else
            {
               rangeShortWaitingReEntry = false;
            }
         }
         else if(stopped && bearIdeaUsed && !bearReEntryUsed && !bearZoneInvalidated)
         {
            bearWaitingReEntry = true;
            lastSignal = "Short stopped: waiting one re-entry confirmation";
         }
         else
         {
            bearWaitingReEntry = false;
         }
      }

      if(deal > lastProcessedCloseDeal)
         lastProcessedCloseDeal = deal;
   }
}

//+------------------------------------------------------------------+
double CalculateLots(double riskDistance)
{
   double riskCash = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPerTradePct / 100.0;
   double tickSize = SymbolInfoDouble(TradeSymbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(TradeSymbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || riskDistance <= 0.0)
      return 0.0;

   double lossPerLot = riskDistance / tickSize * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   return NormalizeLots(riskCash / lossPerLot);
}

double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      return 0.0;

   lots = MathFloor(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   int digits = (int)MathRound(-MathLog10(step));
   return NormalizeDouble(lots, MathMax(0, digits));
}

//+------------------------------------------------------------------+
bool IsNewM15Bar()
{
   datetime t = iTime(TradeSymbol, PERIOD_M15, 0);
   if(t == 0 || t == lastM15BarTime)
      return false;
   lastM15BarTime = t;
   return true;
}

double PipSize()
{
   int digits = (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);
   return digits == 3 || digits == 5 ? point * 10.0 : point;
}

datetime DayStart(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   string text = "EURUSD Playbook Pure Rules EA\n";
   text += "EnableTrading: " + BoolText(EnableTrading) + "\n";
   text += "Risk: " + DoubleToString(RiskPerTradePct, 2) + "% | RR: " + DoubleToString(RR, 2) + "\n";
   text += "SwingLen: " + IntegerToString(SwingLen) + " (1 = 3-candle fractal)\n";
   text += "Fractal stop buffer: " + DoubleToString(FractalStopBufferPips, 1) + " pips\n";
   text += "Last signal: " + lastSignal + "\n";
   text += "Re-entry enabled: " + BoolText(AllowOneReEntry) + "\n";
   text += "FTA RR filter: " + BoolText(UseFtaRrFilter) + " | Min RR to FTA: " + DoubleToString(MinRrToFta, 2) + "\n";
   text += "Pending limit: " + (pendingTicket > 0 ? IntegerToString((long)pendingTicket) : "None") + " | FTA: " + (pendingFtaPrice > 0.0 ? DoubleToString(pendingFtaPrice, _Digits) : "None") + "\n";
   text += "Range active: " + BoolText(rangeActive) + " | Lower/Upper: " + (rangeActive ? DoubleToString(rangeLower, _Digits) + " / " + DoubleToString(rangeUpper, _Digits) : "None") + "\n";
   text += "Range long/short ready: " + BoolText(rangeLongReady) + " / " + BoolText(rangeShortReady) + "\n";
   text += "Bull zone tested/invalid: " + BoolText(bullZoneTested) + " / " + BoolText(bullZoneInvalidated) + "\n";
   text += "Bear zone tested/invalid: " + BoolText(bearZoneTested) + " / " + BoolText(bearZoneInvalidated) + "\n";
   text += "Bull idea/re-entry wait/used: " + BoolText(bullIdeaUsed) + " / " + BoolText(bullWaitingReEntry) + " / " + BoolText(bullReEntryUsed) + "\n";
   text += "Bear idea/re-entry wait/used: " + BoolText(bearIdeaUsed) + " / " + BoolText(bearWaitingReEntry) + " / " + BoolText(bearReEntryUsed) + "\n";
   text += "Last fractal low/high: " + (hasLastFractalLow ? DoubleToString(lastFractalLow, _Digits) : "None") + " / " + (hasLastFractalHigh ? DoubleToString(lastFractalHigh, _Digits) : "None") + "\n";
   text += "Bull zone: " + ZoneText(hasActiveBullZone, activeBullLow, activeBullHigh) + "\n";
   text += "Bear zone: " + ZoneText(hasActiveBearZone, activeBearLow, activeBearHigh);
   Comment(text);
}

string BoolText(bool value)
{
   return value ? "Yes" : "No";
}

string ZoneText(bool active, double low, double high)
{
   if(!active)
      return "None";
   return DoubleToString(low, _Digits) + " - " + DoubleToString(high, _Digits);
}
//+------------------------------------------------------------------+
