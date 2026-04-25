//+------------------------------------------------------------------+
//| EURUSD Playbook FVG Strategy                                     |
//| Mechanical MT5 port of the TradingView EURUSD Playbook strategy. |
//| Default mode is safe: EnableTrading=false.                       |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "EURUSD M15/H4 FVG playbook EA with fixed-risk sizing and prop-firm guard."

#include <Trade/Trade.mqh>

enum TradeDirectionMode
{
   DirectionBoth = 0,
   DirectionLongOnly = 1,
   DirectionShortOnly = 2
};

enum StopLossMode
{
   StopLookbackExtreme = 0,
   StopNearestFractal = 1
};

struct TradePlan
{
   double entry;
   double stop;
   double target;
   double riskDistance;
   double lots;
};

input bool               EnableTrading = false;
input string             TradeSymbol = "EURUSD";
input long               MagicNumber = 26042501;
input double             RR = 2.0;
input TradeDirectionMode TradeDirection = DirectionLongOnly;
input bool               UseNoEntryAfterHour = true;
input int                NoEntryAfterHour = 22;
input bool               RequireM15 = true;
input datetime           BacktestStart = D'2024.01.01 00:00';
input datetime           BacktestEnd = D'2099.12.31 23:59';

input bool               UseStrictConfirmation = false;
input bool               UseHtfBias = false;
input int                HtfFastEmaLen = 50;
input int                HtfSlowEmaLen = 200;
input bool               UseSessionFilter = true;
input int                SessionStartHour = 0;
input int                SessionEndHour = 22;
input bool               UseFtaFilter = false;
input int                FtaLookback = 96;
input double             MinFtaR = 1.2;

input bool               AllowBos = true;
input bool               AllowNewFvg = true;
input bool               AllowIfvg = true;
input int                SwingLen = 2;

input double             RiskPerTradePct = 1.0;
input StopLossMode       StopMode = StopLookbackExtreme;
input int                StopLookback = 15;
input double             MinStopPips = 0.0;
input double             StopBufferPips = 0.5;
input double             FractalStopBufferPips = 2.0;
input bool               UseLookbackFallbackForFractalStop = true;
input bool               UseBreakEven = false;
input double             BreakEvenAtR = 1.0;

input bool               UsePropGuard = true;
input double             DailyDdLimitPct = 5.0;
input double             TotalDdLimitPct = 10.0;
input double             DailyLockBufferPct = 4.5;
input double             TotalLockBufferPct = 9.0;
input bool               UseDynamicRisk = true;
input double             DdLevel1Pct = 3.0;
input double             RiskAtLevel1Pct = 0.5;
input double             DdLevel2Pct = 6.0;
input double             RiskAtLevel2Pct = 0.25;
input bool               CloseOnLimitBreach = false;

CTrade trade;

int fastEmaHandle = INVALID_HANDLE;
int slowEmaHandle = INVALID_HANDLE;
datetime lastM15BarTime = 0;
datetime currentDayStart = 0;

double activeBullLow = 0.0;
double activeBullHigh = 0.0;
double activeBearLow = 0.0;
double activeBearHigh = 0.0;
bool hasActiveBullZone = false;
bool hasActiveBearZone = false;
bool bullZoneTested = false;
bool bearZoneTested = false;

double lastBullFvgLow15 = 0.0;
double lastBullFvgHigh15 = 0.0;
double lastBearFvgLow15 = 0.0;
double lastBearFvgHigh15 = 0.0;
bool hasLastBullFvg15 = false;
bool hasLastBearFvg15 = false;

double lastSwingHigh = 0.0;
double lastSwingLow = 0.0;
bool hasLastSwingHigh = false;
bool hasLastSwingLow = false;

double dayEquityPeak = 0.0;
double totalEquityPeak = 0.0;
double maxDailyDrawdownCash = 0.0;
double maxDailyDrawdownPct = 0.0;
double maxTotalDrawdownCash = 0.0;
double maxTotalDrawdownPct = 0.0;
bool dailyTradingLocked = false;
bool totalTradingLocked = false;
string lastSignal = "None";

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   if(_Symbol != TradeSymbol)
      Print("Warning: EA is configured for ", TradeSymbol, " but chart symbol is ", _Symbol);

   fastEmaHandle = iMA(TradeSymbol, PERIOD_H4, HtfFastEmaLen, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA(TradeSymbol, PERIOD_H4, HtfSlowEmaLen, 0, MODE_EMA, PRICE_CLOSE);
   if(fastEmaHandle == INVALID_HANDLE || slowEmaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA handles.");
      return INIT_FAILED;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   dayEquityPeak = equity;
   totalEquityPeak = equity;
   currentDayStart = DayStart(TimeCurrent());

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(fastEmaHandle != INVALID_HANDLE)
      IndicatorRelease(fastEmaHandle);
   if(slowEmaHandle != INVALID_HANDLE)
      IndicatorRelease(slowEmaHandle);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdatePropGuard();
   ManageOpenPosition();
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

   int m15Count = MathMax(MathMax(FtaLookback + 10, StopLookback + 10), SwingLen * 2 + 10);
   if(CopyRates(TradeSymbol, PERIOD_M15, 0, m15Count, m15) < m15Count)
      return;
   if(CopyRates(TradeSymbol, PERIOD_H4, 0, 10, h4) < 5)
      return;

   UpdateH4Fvg(h4);
   UpdateM15Context(m15);

   bool canTrade = CanOpenNewTrade();
   if(!canTrade)
      return;

   bool allowLongDirection = TradeDirection == DirectionBoth || TradeDirection == DirectionLongOnly;
   bool allowShortDirection = TradeDirection == DirectionBoth || TradeDirection == DirectionShortOnly;
   bool h4BullBias = !UseHtfBias || IsH4BullBias();
   bool h4BearBias = !UseHtfBias || IsH4BearBias();

   bool longDisplacement = (AllowNewFvg && IsNewBullFvg15(m15)) || (AllowIfvg && IsIfvgUp(m15));
   bool shortDisplacement = (AllowNewFvg && IsNewBearFvg15(m15)) || (AllowIfvg && IsIfvgDown(m15));
   bool bosUp = IsBosUp(m15);
   bool bosDown = IsBosDown(m15);

   bool longConfirmation = UseStrictConfirmation ? ((!AllowBos || bosUp) && longDisplacement) : ((AllowBos && bosUp) || longDisplacement);
   bool shortConfirmation = UseStrictConfirmation ? ((!AllowBos || bosDown) && shortDisplacement) : ((AllowBos && bosDown) || shortDisplacement);

   double entryLong = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   double entryShort = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);

   TradePlan longPlan;
   TradePlan shortPlan;
   bool longPlanOk = BuildLongPlan(m15, entryLong, longPlan);
   bool shortPlanOk = BuildShortPlan(m15, entryShort, shortPlan);

   bool longFtaOk = !UseFtaFilter || HasLongFtaSpace(m15, entryLong, longPlan.riskDistance);
   bool shortFtaOk = !UseFtaFilter || HasShortFtaSpace(m15, entryShort, shortPlan.riskDistance);

   if(allowLongDirection && h4BullBias && bullZoneTested && longConfirmation && longPlanOk && longFtaOk)
   {
      lastSignal = "Long signal";
      ExecutePlan(ORDER_TYPE_BUY, longPlan);
      bullZoneTested = false;
      return;
   }

   if(allowShortDirection && h4BearBias && bearZoneTested && shortConfirmation && shortPlanOk && shortFtaOk)
   {
      lastSignal = "Short signal";
      ExecutePlan(ORDER_TYPE_SELL, shortPlan);
      bearZoneTested = false;
   }
}

//+------------------------------------------------------------------+
void UpdateH4Fvg(const MqlRates &h4[])
{
   // Use closed H4 bars: newest closed bar is [1], comparison bar is [3].
   bool bull = h4[1].low > h4[3].high;
   bool bear = h4[1].high < h4[3].low;

   if(bull)
   {
      activeBullLow = h4[3].high;
      activeBullHigh = h4[1].low;
      hasActiveBullZone = true;
      bullZoneTested = false;
   }

   if(bear)
   {
      activeBearLow = h4[1].high;
      activeBearHigh = h4[3].low;
      hasActiveBearZone = true;
      bearZoneTested = false;
   }
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

   UpdateSwingPoints(m15);
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

//+------------------------------------------------------------------+
void UpdateSwingPoints(const MqlRates &m15[])
{
   int pivotIndex = SwingLen + 1;
   bool pivotHigh = true;
   bool pivotLow = true;

   for(int i = pivotIndex - SwingLen; i <= pivotIndex + SwingLen; i++)
   {
      if(i == pivotIndex)
         continue;
      if(m15[pivotIndex].high <= m15[i].high)
         pivotHigh = false;
      if(m15[pivotIndex].low >= m15[i].low)
         pivotLow = false;
   }

   if(pivotHigh)
   {
      lastSwingHigh = m15[pivotIndex].high;
      hasLastSwingHigh = true;
   }
   if(pivotLow)
   {
      lastSwingLow = m15[pivotIndex].low;
      hasLastSwingLow = true;
   }
}

bool IsBosUp(const MqlRates &m15[])
{
   return hasLastSwingHigh && m15[1].close > lastSwingHigh && m15[2].close <= lastSwingHigh;
}

bool IsBosDown(const MqlRates &m15[])
{
   return hasLastSwingLow && m15[1].close < lastSwingLow && m15[2].close >= lastSwingLow;
}

//+------------------------------------------------------------------+
bool BuildLongPlan(const MqlRates &m15[], double entry, TradePlan &plan)
{
   double swingStop = LowestLow(m15, StopLookback, 1);
   double zoneStop = hasActiveBullZone ? activeBullLow : swingStop;
   double pip = PipSize();
   double buffer = StopMode == StopNearestFractal ? FractalStopBufferPips * pip : StopBufferPips * pip;
   double minStopDistance = MinStopPips * pip;
   double stopBase = (entry - swingStop < minStopDistance) ? zoneStop : swingStop;

   if(StopMode == StopNearestFractal)
   {
      if(hasLastSwingLow && lastSwingLow < entry)
         stopBase = lastSwingLow;
      else if(!UseLookbackFallbackForFractalStop)
         return false;
   }

   double stop = NormalizeDouble(stopBase - buffer, (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS));
   double riskDistance = entry - stop;
   if(riskDistance <= SymbolInfoDouble(TradeSymbol, SYMBOL_POINT))
      return false;

   double target = NormalizeDouble(entry + riskDistance * RR, (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS));
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

bool BuildShortPlan(const MqlRates &m15[], double entry, TradePlan &plan)
{
   double swingStop = HighestHigh(m15, StopLookback, 1);
   double zoneStop = hasActiveBearZone ? activeBearHigh : swingStop;
   double pip = PipSize();
   double buffer = StopMode == StopNearestFractal ? FractalStopBufferPips * pip : StopBufferPips * pip;
   double minStopDistance = MinStopPips * pip;
   double stopBase = (swingStop - entry < minStopDistance) ? zoneStop : swingStop;

   if(StopMode == StopNearestFractal)
   {
      if(hasLastSwingHigh && lastSwingHigh > entry)
         stopBase = lastSwingHigh;
      else if(!UseLookbackFallbackForFractalStop)
         return false;
   }

   double stop = NormalizeDouble(stopBase + buffer, (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS));
   double riskDistance = stop - entry;
   if(riskDistance <= SymbolInfoDouble(TradeSymbol, SYMBOL_POINT))
      return false;

   double target = NormalizeDouble(entry - riskDistance * RR, (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS));
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
void ExecutePlan(ENUM_ORDER_TYPE orderType, const TradePlan &plan)
{
   string side = orderType == ORDER_TYPE_BUY ? "BUY" : "SELL";
   Print(side, " signal: lots=", DoubleToString(plan.lots, 2), " entry=", DoubleToString(plan.entry, _Digits), " sl=", DoubleToString(plan.stop, _Digits), " tp=", DoubleToString(plan.target, _Digits), " risk%=", DoubleToString(CurrentRiskPct(), 2));

   if(!EnableTrading)
   {
      Print("EnableTrading=false. Signal logged only, no order sent.");
      return;
   }

   bool ok = false;
   if(orderType == ORDER_TYPE_BUY)
      ok = trade.Buy(plan.lots, TradeSymbol, 0.0, plan.stop, plan.target, "EURUSD Playbook FVG Long");
   else
      ok = trade.Sell(plan.lots, TradeSymbol, 0.0, plan.stop, plan.target, "EURUSD Playbook FVG Short");

   if(!ok)
      Print("Order failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
bool CanOpenNewTrade()
{
   datetime now = TimeCurrent();
   if(now < BacktestStart || now > BacktestEnd)
      return false;
   if(HasOpenPosition())
      return false;

   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(UseNoEntryAfterHour && dt.hour >= NoEntryAfterHour)
      return false;
   if(UseSessionFilter && (dt.hour < SessionStartHour || dt.hour >= SessionEndHour))
      return false;
   if(!PropTradingAllowed())
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

//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(CloseOnLimitBreach && UsePropGuard && (CurrentDailyDdPct() >= DailyDdLimitPct || CurrentTotalDdPct() >= TotalDdLimitPct))
      CloseOwnPositions("Prop limit breach");

   if(!UseBreakEven)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != TradeSymbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      if(sl <= 0.0 || tp <= 0.0)
         continue;

      double risk = type == POSITION_TYPE_BUY ? openPrice - sl : sl - openPrice;
      if(risk <= 0.0)
         continue;

      if(type == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
         if(bid >= openPrice + risk * BreakEvenAtR && sl < openPrice)
            trade.PositionModify(ticket, NormalizeDouble(openPrice, _Digits), tp);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
         if(ask <= openPrice - risk * BreakEvenAtR && sl > openPrice)
            trade.PositionModify(ticket, NormalizeDouble(openPrice, _Digits), tp);
      }
   }
}

void CloseOwnPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == TradeSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         Print("Closing position: ", reason);
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
double CalculateLots(double riskDistance)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskCash = equity * CurrentRiskPct() / 100.0;
   double tickSize = SymbolInfoDouble(TradeSymbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(TradeSymbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || riskDistance <= 0.0)
      return 0.0;

   double lossPerLot = riskDistance / tickSize * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   double lots = riskCash / lossPerLot;
   return NormalizeLots(lots);
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
void UpdatePropGuard()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime dayStart = DayStart(TimeCurrent());
   if(dayStart != currentDayStart)
   {
      currentDayStart = dayStart;
      dayEquityPeak = equity;
      dailyTradingLocked = false;
   }

   dayEquityPeak = MathMax(dayEquityPeak, equity);
   totalEquityPeak = MathMax(totalEquityPeak, equity);

   double dailyCash = MathMax(dayEquityPeak - equity, 0.0);
   double totalCash = MathMax(totalEquityPeak - equity, 0.0);
   double dailyPct = dayEquityPeak > 0.0 ? dailyCash / dayEquityPeak * 100.0 : 0.0;
   double totalPct = totalEquityPeak > 0.0 ? totalCash / totalEquityPeak * 100.0 : 0.0;

   maxDailyDrawdownCash = MathMax(maxDailyDrawdownCash, dailyCash);
   maxDailyDrawdownPct = MathMax(maxDailyDrawdownPct, dailyPct);
   maxTotalDrawdownCash = MathMax(maxTotalDrawdownCash, totalCash);
   maxTotalDrawdownPct = MathMax(maxTotalDrawdownPct, totalPct);

   if(UsePropGuard && dailyPct >= DailyLockBufferPct)
      dailyTradingLocked = true;
   if(UsePropGuard && totalPct >= TotalLockBufferPct)
      totalTradingLocked = true;
}

bool PropTradingAllowed()
{
   if(!UsePropGuard)
      return true;
   if(dailyTradingLocked || totalTradingLocked)
      return false;
   return CurrentDailyDdPct() < DailyDdLimitPct && CurrentTotalDdPct() < TotalDdLimitPct;
}

double CurrentRiskPct()
{
   double totalDd = CurrentTotalDdPct();
   if(UsePropGuard && UseDynamicRisk && totalDd >= DdLevel2Pct)
      return RiskAtLevel2Pct;
   if(UsePropGuard && UseDynamicRisk && totalDd >= DdLevel1Pct)
      return RiskAtLevel1Pct;
   return RiskPerTradePct;
}

double CurrentDailyDdPct()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return dayEquityPeak > 0.0 ? MathMax(dayEquityPeak - equity, 0.0) / dayEquityPeak * 100.0 : 0.0;
}

double CurrentTotalDdPct()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return totalEquityPeak > 0.0 ? MathMax(totalEquityPeak - equity, 0.0) / totalEquityPeak * 100.0 : 0.0;
}

//+------------------------------------------------------------------+
bool IsH4BullBias()
{
   double fast[], slow[], closeRates[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(closeRates, true);
   if(CopyBuffer(fastEmaHandle, 0, 1, 1, fast) < 1)
      return false;
   if(CopyBuffer(slowEmaHandle, 0, 1, 1, slow) < 1)
      return false;
   if(CopyClose(TradeSymbol, PERIOD_H4, 1, 1, closeRates) < 1)
      return false;
   return closeRates[0] > fast[0] && fast[0] > slow[0];
}

bool IsH4BearBias()
{
   double fast[], slow[], closeRates[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(closeRates, true);
   if(CopyBuffer(fastEmaHandle, 0, 1, 1, fast) < 1)
      return false;
   if(CopyBuffer(slowEmaHandle, 0, 1, 1, slow) < 1)
      return false;
   if(CopyClose(TradeSymbol, PERIOD_H4, 1, 1, closeRates) < 1)
      return false;
   return closeRates[0] < fast[0] && fast[0] < slow[0];
}

//+------------------------------------------------------------------+
bool HasLongFtaSpace(const MqlRates &m15[], double entry, double riskDistance)
{
   double fta = HighestHigh(m15, FtaLookback, 1);
   return (fta - entry) > riskDistance * MinFtaR;
}

bool HasShortFtaSpace(const MqlRates &m15[], double entry, double riskDistance)
{
   double fta = LowestLow(m15, FtaLookback, 1);
   return (entry - fta) > riskDistance * MinFtaR;
}

double LowestLow(const MqlRates &rates[], int lookback, int startIndex)
{
   double result = rates[startIndex].low;
   for(int i = startIndex; i < startIndex + lookback; i++)
      result = MathMin(result, rates[i].low);
   return result;
}

double HighestHigh(const MqlRates &rates[], int lookback, int startIndex)
{
   double result = rates[startIndex].high;
   for(int i = startIndex; i < startIndex + lookback; i++)
      result = MathMax(result, rates[i].high);
   return result;
}

//+------------------------------------------------------------------+
bool IsNewM15Bar()
{
   datetime t = iTime(TradeSymbol, PERIOD_M15, 0);
   if(t == 0)
      return false;
   if(t == lastM15BarTime)
      return false;
   lastM15BarTime = t;
   return true;
}

datetime DayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

double PipSize()
{
   int digits = (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(TradeSymbol, SYMBOL_POINT);
   return digits == 3 || digits == 5 ? point * 10.0 : point;
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   int maxLossStreak = 0;
   int maxWinStreak = 0;
   CalculateStreaks(maxLossStreak, maxWinStreak);

   string text = "EURUSD Playbook FVG Strategy\n";
   text += "EnableTrading: " + BoolText(EnableTrading) + "\n";
   text += "Last signal: " + lastSignal + "\n";
   text += "Stop mode: " + StopModeText() + "\n";
   text += "Risk now: " + DoubleToString(CurrentRiskPct(), 2) + "%\n";
   text += "Daily DD: " + DoubleToString(CurrentDailyDdPct(), 2) + "% / max " + DoubleToString(maxDailyDrawdownPct, 2) + "%\n";
   text += "Total DD: " + DoubleToString(CurrentTotalDdPct(), 2) + "% / max " + DoubleToString(maxTotalDrawdownPct, 2) + "%\n";
   text += "Daily locked: " + BoolText(dailyTradingLocked) + " | Total locked: " + BoolText(totalTradingLocked) + "\n";
   text += "Prop allowed: " + BoolText(PropTradingAllowed()) + "\n";
   text += "Max losing streak: " + IntegerToString(maxLossStreak) + " | Max winning streak: " + IntegerToString(maxWinStreak) + "\n";
   text += "Last swing low/high: " + (hasLastSwingLow ? DoubleToString(lastSwingLow, _Digits) : "None") + " / " + (hasLastSwingHigh ? DoubleToString(lastSwingHigh, _Digits) : "None") + "\n";
   text += "Bull zone: " + ZoneText(hasActiveBullZone, activeBullLow, activeBullHigh) + "\n";
   text += "Bear zone: " + ZoneText(hasActiveBearZone, activeBearLow, activeBearHigh);
   Comment(text);
}

void CalculateStreaks(int &maxLossStreak, int &maxWinStreak)
{
   if(!HistorySelect(0, TimeCurrent()))
      return;

   int currentLoss = 0;
   int currentWin = 0;
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

      double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + HistoryDealGetDouble(deal, DEAL_COMMISSION);
      if(profit < 0.0)
      {
         currentLoss++;
         currentWin = 0;
         maxLossStreak = MathMax(maxLossStreak, currentLoss);
      }
      else if(profit > 0.0)
      {
         currentWin++;
         currentLoss = 0;
         maxWinStreak = MathMax(maxWinStreak, currentWin);
      }
   }
}

string BoolText(bool value)
{
   return value ? "Yes" : "No";
}

string StopModeText()
{
   if(StopMode == StopNearestFractal)
      return "Nearest fractal + " + DoubleToString(FractalStopBufferPips, 1) + " pips";
   return "Lookback extreme + " + DoubleToString(StopBufferPips, 1) + " pips";
}

string ZoneText(bool active, double low, double high)
{
   if(!active)
      return "None";
   return DoubleToString(low, _Digits) + " - " + DoubleToString(high, _Digits);
}
//+------------------------------------------------------------------+
