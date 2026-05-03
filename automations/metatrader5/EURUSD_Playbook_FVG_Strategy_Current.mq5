//+------------------------------------------------------------------+
//| EURUSD Playbook FVG Strategy - Current MT5 Port                   |
//| Mechanical Expert Advisor port of scripts/current.pine.           |
//| Safe by default: EnableTrading=false logs signals only.            |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "EURUSD M15/H4 FVG playbook EA ported from the current TradingView Pine strategy."

#include <Trade/Trade.mqh>

enum ExecutionProfileMode
{
   ProfilePropPass45 = 0,
   ProfilePropConservative = 1,
   ProfilePropBalanced = 2,
   ProfilePropGrowth = 3,
   ProfileAggressive = 4,
   ProfileCustom = 5
};

enum TradeDirectionMode
{
   DirectionBoth = 0,
   DirectionLongOnly = 1,
   DirectionShortOnly = 2
};

enum RangeTargetMode
{
   RangeTargetMidline = 0,
   RangeTargetOppositeBoundary = 1,
   RangeTargetAdaptive = 2
};

struct TradePlan
{
   string entryName;
   ENUM_ORDER_TYPE orderType;
   double entry;
   double stop;
   double target;
   double riskDistance;
   double lots;
   double targetR;
   bool useLimit;
};

struct SignalContext
{
   bool bosUp;
   bool bosDown;
   bool longDisplacement;
   bool shortDisplacement;
   bool longConfirmation;
   bool shortConfirmation;
   bool longFtaOk;
   bool shortFtaOk;
   bool longRangeLocationOk;
   bool shortRangeLocationOk;
   int longQualityScore;
   int shortQualityScore;
   double atr;
   double atrPips;
   double longFtaR;
   double shortFtaR;
};

input bool                 EnableTrading = false;
input string               TradeSymbol = "EURUSD";
input long                 MagicNumber = 26042601;
input int                  DeviationPoints = 20;

input ExecutionProfileMode ExecutionProfile = ProfilePropPass45;
input double               RR = 2.0;
input TradeDirectionMode   TradeDirection = DirectionLongOnly;
input bool                 UseNoEntryAfterHour = false;
input int                  NoEntryAfterHour = 22;
input int                  EntryHourOffset = 0;       // Add hours to broker server time to match Pine timezone.
input bool                 RequireM15 = true;
input datetime             BacktestStart = D'2024.01.01 00:00';
input datetime             BacktestEnd = D'2099.12.31 23:59';

input bool                 UseStrictConfirmation = false;
input bool                 UseHtfBias = false;
input int                  HtfFastEmaLen = 50;
input int                  HtfSlowEmaLen = 200;
input bool                 UseSessionFilter = true;
input int                  SessionStartHour = 8;
input int                  SessionEndHour = 18;
input bool                 UseFtaFilter = true;
input int                  FtaLookback = 96;
input double               MinFtaR = 1.2;
input int                  MaxHtfFvgAge = 32;
input double               MinConfirmationAtr = 0.25;
input int                  MaxBarsAfterZoneTest = 8;
input bool                 UsePullbackLimitEntry = true;
input int                  MaxDailyLosses = 2;
input bool                 UseControlledReentry = true;
input int                  MaxReentriesPerZone = 1;
input bool                 UseQualityFilter = true;
input int                  MinQualityScore = 5;
input int                  RangeLookback = 48;
input bool                 UseAtrVolFilter = true;
input double               MinAtrPips = 2.2;
input bool                 UseAdaptiveTargets = true;
input int                  HighQualityTargetScore = 5;
input double               ExtendedTargetR = 3.5;

input bool                 UseRangeModule = false;
input int                  RangeLookbackHtf = 24;
input int                  RangeAtrLen = 14;
input double               RangeCompressionAtr = 8.0;
input double               RangeBoundaryPct = 0.10;
input bool                 AllowRangeLongs = true;
input bool                 AllowRangeShorts = false;
input bool                 UseRangeSweepEntry = true;
input bool                 UseRangeFvgConfirm = true;
input RangeTargetMode      RangeTarget = RangeTargetAdaptive;
input double               RangeRiskMultiplier = 0.5;
input double               MinRangeTargetR = 2.5;
input int                  MinRangeQualityScore = 6;
input double               MaxRangeStopPips = 18.0;
input int                  RangeInvalidCloses = 2;

input bool                 UseLondonOpenSetup = false;
input int                  AsiaStartHour = 0;
input int                  AsiaEndHour = 8;
input int                  LondonEntryHour = 9;
input double               LondonTargetR = 1.5;
input double               LondonRiskMultiplier = 0.75;
input double               MaxLondonStopPips = 22.0;

input bool                 AllowBos = true;
input bool                 AllowNewFvg = true;
input bool                 AllowIfvg = true;
input int                  SwingLen = 2;

input double               RiskPerTradePct = 1.0;
input int                  StopLookback = 15;
input double               MinStopPips = 0.0;
input double               MaxStopPips = 22.0;
input double               MaxStopAtr = 3.0;
input double               StopBufferPips = 0.5;
input bool                 UseBreakEven = false;
input double               BreakEvenAtR = 1.0;
input double               BreakEvenPlusR = 0.1;
input bool                 UsePartialTakeProfit = true;
input double               PartialTpR = 2.0;
input double               PartialQtyPct = 70.0;
input double               RunnerTpR = 3.0;

input bool                 UsePropGuard = true;
input double               DailyDdLimitPct = 5.0;
input double               TotalDdLimitPct = 10.0;
input double               DailyLockBufferPct = 4.5;
input double               TotalLockBufferPct = 9.0;
input bool                 UseDynamicRisk = true;
input double               DdLevel1Pct = 3.0;
input double               RiskAtLevel1Pct = 0.5;
input double               DdLevel2Pct = 6.0;
input double               RiskAtLevel2Pct = 0.25;
input bool                 CloseOnLimitBreach = false;

CTrade trade;

int fastEmaHandle = INVALID_HANDLE;
int slowEmaHandle = INVALID_HANDLE;
datetime lastM15BarTime = 0;
datetime lastClosedH4Time = 0;
datetime currentDayStart = 0;
ulong lastProcessedCloseDeal = 0;

double activeBullLow = 0.0;
double activeBullHigh = 0.0;
double activeBearLow = 0.0;
double activeBearHigh = 0.0;
bool hasActiveBullZone = false;
bool hasActiveBearZone = false;
bool bullZoneTested = false;
bool bearZoneTested = false;
int bullZoneAge = 100000;
int bearZoneAge = 100000;
bool bullZoneTraded = false;
bool bearZoneTraded = false;
int bullZoneReentries = 0;
int bearZoneReentries = 0;
int bullBarsAfterTest = 100000;
int bearBarsAfterTest = 100000;

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
int dailyLossCount = 0;

double asiaLow = 0.0;
double asiaHigh = 0.0;
bool hasAsiaLow = false;
bool hasAsiaHigh = false;
bool londonBullNightTest = false;
bool londonBearNightTest = false;
bool londonTradeTaken = false;
int rangeClosesAbove = 0;
int rangeClosesBelow = 0;

bool partialClosed = false;
string activeEntryName = "";
double activeInitialStop = 0.0;
double activeRisk = 0.0;
string lastSignal = "None";

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);

   if(_Symbol != TradeSymbol)
      Print("Warning: EA is configured for ", TradeSymbol, " but chart symbol is ", _Symbol);

   fastEmaHandle = iMA(TradeSymbol, PERIOD_H4, HtfFastEmaLen, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA(TradeSymbol, PERIOD_H4, HtfSlowEmaLen, 0, MODE_EMA, PRICE_CLOSE);
   if(fastEmaHandle == INVALID_HANDLE || slowEmaHandle == INVALID_HANDLE)
   {
      Print("Failed to create H4 EMA handles.");
      return INIT_FAILED;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   dayEquityPeak = equity;
   totalEquityPeak = equity;
   currentDayStart = DayStart(AdjustedTime(TimeCurrent()));
   InitializeLastProcessedCloseDeal();
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
   UpdateDailyLossCount();
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

   int needM15 = MathMax(MathMax(FtaLookback + 20, StopLookback + 20), MathMax(RangeLookback + 20, SwingLen * 2 + 30));
   int needH4 = MathMax(MathMax(RangeLookbackHtf + 20, RangeAtrLen + 20), 10);
   if(CopyRates(TradeSymbol, PERIOD_M15, 0, needM15, m15) < needM15)
      return;
   if(CopyRates(TradeSymbol, PERIOD_H4, 0, needH4, h4) < needH4)
      return;

   bool h4NewBar = UpdateH4Fvg(h4, m15);
   UpdateRangeInvalidation(h4, h4NewBar);
   UpdateM15Context(m15);
   UpdateAsiaLondonState(m15);

   if(!CanOpenNewTrade())
      return;

   SignalContext ctx;
   BuildSignalContext(m15, ctx);

   TradePlan longPlan;
   TradePlan shortPlan;
   TradePlan rangeLongPlan;
   TradePlan rangeShortPlan;
   TradePlan londonLongPlan;
   TradePlan londonShortPlan;
   bool longPlanOk = BuildMainPlan(true, m15, ctx, longPlan);
   bool shortPlanOk = BuildMainPlan(false, m15, ctx, shortPlan);
   bool rangeLongOk = BuildRangePlan(true, m15, h4, ctx, rangeLongPlan);
   bool rangeShortOk = BuildRangePlan(false, m15, h4, ctx, rangeShortPlan);
   bool londonLongOk = BuildLondonPlan(true, m15, ctx, londonLongPlan);
   bool londonShortOk = BuildLondonPlan(false, m15, ctx, londonShortPlan);

   bool allowLongDirection = TradeDirection == DirectionBoth || TradeDirection == DirectionLongOnly;
   bool allowShortDirection = TradeDirection == DirectionBoth || TradeDirection == DirectionShortOnly;
   bool h4BullBias = !UseHtfBiasActive() || IsH4BullBias();
   bool h4BearBias = !UseHtfBiasActive() || IsH4BearBias();
   bool bullZoneFresh = bullZoneAge <= MaxHtfFvgAge;
   bool bearZoneFresh = bearZoneAge <= MaxHtfFvgAge;
   bool bullTestFresh = bullBarsAfterTest <= MaxBarsAfterZoneTest;
   bool bearTestFresh = bearBarsAfterTest <= MaxBarsAfterZoneTest;
   bool bullZoneReclaimed = hasActiveBullZone && m15[1].close > activeBullHigh;
   bool bearZoneRejected = hasActiveBearZone && m15[1].close < activeBearLow;
   bool dailyLossCooldown = dailyLossCount >= MaxDailyLossesActive();
   bool common = IsEurUsd() && IsInBacktestWindow(m15[1].time) && InEntrySession(m15[1].time) && PropTradingAllowed() && !dailyLossCooldown && !HasOpenPosition() && !HasOwnPendingOrders();

   bool longReady = common && allowLongDirection && h4BullBias && bullZoneFresh && !bullZoneTraded && bullZoneTested && bullTestFresh && bullZoneReclaimed && ctx.longConfirmation && longPlanOk;
   bool shortReady = common && allowShortDirection && h4BearBias && bearZoneFresh && !bearZoneTraded && bearZoneTested && bearTestFresh && bearZoneRejected && ctx.shortConfirmation && shortPlanOk;

   if(longReady)
   {
      bool reentry = bullZoneReentries > 0;
      lastSignal = reentry ? "Long re-entry" : "Long";
      ExecutePlan(longPlan);
      bullZoneTested = false;
      bullZoneTraded = true;
      return;
   }

   if(rangeLongOk && !longReady)
   {
      lastSignal = "Range Long";
      ExecutePlan(rangeLongPlan);
      return;
   }

   if(londonLongOk && !longReady && !rangeLongOk)
   {
      lastSignal = "London Long";
      ExecutePlan(londonLongPlan);
      londonTradeTaken = true;
      return;
   }

   if(shortReady)
   {
      bool reentry = bearZoneReentries > 0;
      lastSignal = reentry ? "Short re-entry" : "Short";
      ExecutePlan(shortPlan);
      bearZoneTested = false;
      bearZoneTraded = true;
      return;
   }

   if(rangeShortOk && !shortReady)
   {
      lastSignal = "Range Short";
      ExecutePlan(rangeShortPlan);
      return;
   }

   if(londonShortOk && !shortReady && !rangeShortOk)
   {
      lastSignal = "London Short";
      ExecutePlan(londonShortPlan);
      londonTradeTaken = true;
   }
}

//+------------------------------------------------------------------+
bool UpdateH4Fvg(const MqlRates &h4[], const MqlRates &m15[])
{
   bool h4NewBar = h4[1].time != lastClosedH4Time;
   if(h4NewBar)
   {
      lastClosedH4Time = h4[1].time;
      bullZoneAge++;
      bearZoneAge++;
   }

   if(h4NewBar && h4[1].low > h4[3].high)
   {
      activeBullLow = h4[3].high;
      activeBullHigh = h4[1].low;
      hasActiveBullZone = true;
      bullZoneTested = false;
      bullZoneAge = 0;
      bullZoneTraded = false;
      bullZoneReentries = 0;
      bullBarsAfterTest = 100000;
   }

   if(h4NewBar && h4[1].high < h4[3].low)
   {
      activeBearLow = h4[1].high;
      activeBearHigh = h4[3].low;
      hasActiveBearZone = true;
      bearZoneTested = false;
      bearZoneAge = 0;
      bearZoneTraded = false;
      bearZoneReentries = 0;
      bearBarsAfterTest = 100000;
   }

   if(hasActiveBullZone && m15[1].close < activeBullLow)
   {
      hasActiveBullZone = false;
      bullZoneTested = false;
      bullZoneTraded = false;
      bullZoneReentries = 0;
      bullBarsAfterTest = 100000;
   }

   if(hasActiveBearZone && m15[1].close > activeBearHigh)
   {
      hasActiveBearZone = false;
      bearZoneTested = false;
      bearZoneTraded = false;
      bearZoneReentries = 0;
      bearBarsAfterTest = 100000;
   }
   return h4NewBar;
}

//+------------------------------------------------------------------+
void UpdateM15Context(const MqlRates &m15[])
{
   bool bullZoneTouched = hasActiveBullZone && m15[1].low <= activeBullHigh && m15[1].high >= activeBullLow;
   bool bearZoneTouched = hasActiveBearZone && m15[1].high >= activeBearLow && m15[1].low <= activeBearHigh;

   if(bullZoneTouched)
   {
      bullZoneTested = true;
      bullBarsAfterTest = 0;
   }
   if(bearZoneTouched)
   {
      bearZoneTested = true;
      bearBarsAfterTest = 0;
   }
   if(bullZoneTested && !bullZoneTouched)
      bullBarsAfterTest++;
   if(bearZoneTested && !bearZoneTouched)
      bearBarsAfterTest++;

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
void BuildSignalContext(const MqlRates &m15[], SignalContext &ctx)
{
   ctx.bosUp = IsBosUp(m15);
   ctx.bosDown = IsBosDown(m15);
   ctx.longDisplacement = (AllowNewFvg && IsNewBullFvg15(m15)) || (AllowIfvg && IsIfvgUp(m15));
   ctx.shortDisplacement = (AllowNewFvg && IsNewBearFvg15(m15)) || (AllowIfvg && IsIfvgDown(m15));
   ctx.atr = Atr(m15, 14, 1);
   ctx.atrPips = ctx.atr / PipSize();
   double body = MathAbs(m15[1].close - m15[1].open);
   bool confirmationStrong = MinConfirmationAtr <= 0.0 || (ctx.atr > 0.0 && body >= ctx.atr * MinConfirmationAtr);
   ctx.longConfirmation = confirmationStrong && (UseStrictConfirmationActive() ? ((!AllowBos || ctx.bosUp) && ctx.longDisplacement) : ((AllowBos && ctx.bosUp) || ctx.longDisplacement));
   ctx.shortConfirmation = confirmationStrong && (UseStrictConfirmationActive() ? ((!AllowBos || ctx.bosDown) && ctx.shortDisplacement) : ((AllowBos && ctx.bosDown) || ctx.shortDisplacement));

   double longFtaSpace = HighestHigh(m15, FtaLookback, 1) - m15[1].close;
   double shortFtaSpace = m15[1].close - LowestLow(m15, FtaLookback, 1);
   double rangeHigh = HighestHigh(m15, RangeLookback, 1);
   double rangeLow = LowestLow(m15, RangeLookback, 1);
   double rangeSize = rangeHigh - rangeLow;
   double rangePos = rangeSize > PointSize() ? (m15[1].close - rangeLow) / rangeSize : 0.5;
   ctx.longRangeLocationOk = rangeSize <= PointSize() || rangePos <= 0.70;
   ctx.shortRangeLocationOk = rangeSize <= PointSize() || rangePos >= 0.30;

   double longRisk = EstimateMainRisk(true, m15, m15[1].close);
   double shortRisk = EstimateMainRisk(false, m15, m15[1].close);
   ctx.longFtaOk = !UseFtaFilterActive() || (longRisk > PointSize() && longFtaSpace > longRisk * MinFtaR);
   ctx.shortFtaOk = !UseFtaFilterActive() || (shortRisk > PointSize() && shortFtaSpace > shortRisk * MinFtaR);
   ctx.longFtaR = longRisk > PointSize() ? longFtaSpace / longRisk : 0.0;
   ctx.shortFtaR = shortRisk > PointSize() ? shortFtaSpace / shortRisk : 0.0;

   int freshHalf = MathMax(1, MaxHtfFvgAge / 2);
   int testFast = MathMin(MaxBarsAfterZoneTest, 4);
   ctx.longQualityScore = (bullZoneAge <= freshHalf ? 1 : 0) + (bullBarsAfterTest <= testFast ? 1 : 0) + (ctx.bosUp ? 1 : 0) + (ctx.longDisplacement ? 1 : 0) + (body >= ctx.atr * 0.35 ? 1 : 0) + (ctx.longFtaOk ? 1 : 0) + (ctx.longRangeLocationOk ? 1 : 0);
   ctx.shortQualityScore = (bearZoneAge <= freshHalf ? 1 : 0) + (bearBarsAfterTest <= testFast ? 1 : 0) + (ctx.bosDown ? 1 : 0) + (ctx.shortDisplacement ? 1 : 0) + (body >= ctx.atr * 0.35 ? 1 : 0) + (ctx.shortFtaOk ? 1 : 0) + (ctx.shortRangeLocationOk ? 1 : 0);
}

//+------------------------------------------------------------------+
bool BuildMainPlan(bool isLong, const MqlRates &m15[], const SignalContext &ctx, TradePlan &plan)
{
   double entry = m15[1].close;
   bool useLimit = UsePullbackLimitEntryActive();
   if(isLong && useLimit && hasActiveBullZone)
      entry = activeBullHigh;
   if(!isLong && useLimit && hasActiveBearZone)
      entry = activeBearLow;

   double risk = EstimateMainRisk(isLong, m15, entry);
   if(risk <= PointSize())
      return false;

   double stop = isLong ? entry - risk : entry + risk;
   double riskPips = risk / PipSize();
   if(riskPips > MaxStopPips || risk > ctx.atr * MaxStopAtr)
      return false;
   if(UseAtrVolFilter && ctx.atrPips < MinAtrPips)
      return false;

   bool qualityOk = !UseQualityFilter || (isLong ? ctx.longQualityScore : ctx.shortQualityScore) >= MinQualityScoreActive();
   if(!qualityOk)
      return false;
   if(isLong && !ctx.longFtaOk)
      return false;
   if(!isLong && !ctx.shortFtaOk)
      return false;

   int quality = isLong ? ctx.longQualityScore : ctx.shortQualityScore;
   double ftaR = isLong ? ctx.longFtaR : ctx.shortFtaR;
   double targetR = UseAdaptiveTargetsActive() && quality >= HighQualityTargetScore && ftaR >= ExtendedTargetR ? ExtendedTargetR : RRActive();
   double effectiveTargetR = UsePartialTakeProfitActive() ? RunnerTpRActive() : targetR;
   double target = isLong ? entry + risk * effectiveTargetR : entry - risk * effectiveTargetR;
   double lots = CalculateLots(risk, CurrentRiskPct());
   if(lots <= 0.0)
      return false;

   plan.entryName = isLong ? "Long" : "Short";
   plan.orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   plan.entry = NormalizePrice(entry);
   plan.stop = NormalizePrice(stop);
   plan.target = NormalizePrice(target);
   plan.riskDistance = risk;
   plan.lots = lots;
   plan.targetR = targetR;
   plan.useLimit = useLimit;
   return true;
}

bool BuildRangePlan(bool isLong, const MqlRates &m15[], const MqlRates &h4[], const SignalContext &ctx, TradePlan &plan)
{
   double rangeHigh, rangeLow, rangeAtr;
   if(!GetH4Range(h4, rangeHigh, rangeLow, rangeAtr))
      return false;
   double size = rangeHigh - rangeLow;
   if(!UseRangeModule || size <= PointSize() || rangeAtr <= PointSize() || size > rangeAtr * RangeCompressionAtr)
      return false;
   if(m15[1].close < rangeLow || m15[1].close > rangeHigh || rangeClosesAbove >= RangeInvalidCloses || rangeClosesBelow >= RangeInvalidCloses)
      return false;

   double pos = (m15[1].close - rangeLow) / size;
   bool nearLow = pos <= RangeBoundaryPct;
   bool nearHigh = pos >= 1.0 - RangeBoundaryPct;
   bool sweepLong = m15[1].low < rangeLow && m15[1].close > rangeLow;
   bool sweepShort = m15[1].high > rangeHigh && m15[1].close < rangeHigh;
   bool boundaryLong = m15[1].low <= rangeLow + size * RangeBoundaryPct && m15[1].close > rangeLow;
   bool boundaryShort = m15[1].high >= rangeHigh - size * RangeBoundaryPct && m15[1].close < rangeHigh;
   bool confirm = isLong ? (!UseRangeFvgConfirm || ctx.longConfirmation) : (!UseRangeFvgConfirm || ctx.shortConfirmation);
   bool location = isLong ? (nearLow && (UseRangeSweepEntry ? sweepLong : boundaryLong)) : (nearHigh && (UseRangeSweepEntry ? sweepShort : boundaryShort));
   int quality = isLong ? ctx.longQualityScore : ctx.shortQualityScore;
   if(!confirm || !location || quality < MinRangeQualityScore)
      return false;
   if(isLong && !AllowRangeLongs)
      return false;
   if(!isLong && !AllowRangeShorts)
      return false;

   double entry = m15[1].close;
   double stop = isLong ? MathMin(m15[1].low, rangeLow) - StopBufferPips * PipSize() : MathMax(m15[1].high, rangeHigh) + StopBufferPips * PipSize();
   double risk = isLong ? entry - stop : stop - entry;
   if(risk <= PointSize() || risk / PipSize() > MaxRangeStopPips || risk > ctx.atr * MaxStopAtr)
      return false;
   if(UseAtrVolFilter && ctx.atrPips < MinAtrPips)
      return false;
   double mid = (rangeHigh + rangeLow) / 2.0;
   double target = isLong ? RangeTargetPrice(true, rangeHigh, mid, quality) : RangeTargetPrice(false, rangeLow, mid, quality);
   double targetR = isLong ? (target - entry) / risk : (entry - target) / risk;
   if(targetR < MinRangeTargetR)
      return false;
   double lots = CalculateLots(risk, CurrentRiskPct() * RangeRiskMultiplier);
   if(lots <= 0.0)
      return false;

   plan.entryName = isLong ? "Range Long" : "Range Short";
   plan.orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   plan.entry = NormalizePrice(entry);
   plan.stop = NormalizePrice(stop);
   plan.target = NormalizePrice(target);
   plan.riskDistance = risk;
   plan.lots = lots;
   plan.targetR = targetR;
   plan.useLimit = false;
   return IsEurUsd() && InEntrySession(m15[1].time) && PropTradingAllowed() && !HasOpenPosition() && !HasOwnPendingOrders();
}

bool BuildLondonPlan(bool isLong, const MqlRates &m15[], const SignalContext &ctx, TradePlan &plan)
{
   if(ExecutionProfile != ProfilePropGrowth || !UseLondonOpenSetup || londonTradeTaken || EntryHour(m15[1].time) != LondonEntryHour)
      return false;
   if(isLong && (!AllowLongDirection() || !londonBullNightTest || !hasActiveBullZone || m15[1].close <= activeBullHigh || !(ctx.longConfirmation || ConfirmationStrong(m15))))
      return false;
   if(!isLong && (!AllowShortDirection() || !londonBearNightTest || !hasActiveBearZone || m15[1].close >= activeBearLow || !(ctx.shortConfirmation || ConfirmationStrong(m15))))
      return false;

   double entry = m15[1].close;
   double stop = 0.0;
   if(isLong)
   {
      if(!hasAsiaLow)
         return false;
      stop = MathMin(asiaLow, activeBullLow) - StopBufferPips * PipSize();
   }
   else
   {
      if(!hasAsiaHigh)
         return false;
      stop = MathMax(asiaHigh, activeBearHigh) + StopBufferPips * PipSize();
   }
   double risk = isLong ? entry - stop : stop - entry;
   if(risk <= PointSize() || risk / PipSize() > MaxLondonStopPips || risk > ctx.atr * MaxStopAtr)
      return false;
   double target = isLong ? entry + risk * LondonTargetR : entry - risk * LondonTargetR;
   double lots = CalculateLots(risk, CurrentRiskPct() * LondonRiskMultiplier);
   if(lots <= 0.0)
      return false;

   plan.entryName = isLong ? "London Long" : "London Short";
   plan.orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   plan.entry = NormalizePrice(entry);
   plan.stop = NormalizePrice(stop);
   plan.target = NormalizePrice(target);
   plan.riskDistance = risk;
   plan.lots = lots;
   plan.targetR = LondonTargetR;
   plan.useLimit = false;
   return IsEurUsd() && PropTradingAllowed() && !HasOpenPosition() && !HasOwnPendingOrders();
}

//+------------------------------------------------------------------+
double EstimateMainRisk(bool isLong, const MqlRates &m15[], double entry)
{
   double pip = PipSize();
   double minStopDistance = MinStopPips * pip;
   if(isLong)
   {
      double swingStop = LowestLow(m15, StopLookback, 1);
      double zoneStop = hasActiveBullZone ? activeBullLow : swingStop;
      double stopBase = (entry - swingStop < minStopDistance) ? zoneStop : swingStop;
      double stop = stopBase - StopBufferPips * pip;
      return entry - stop;
   }
   double swingStop = HighestHigh(m15, StopLookback, 1);
   double zoneStop = hasActiveBearZone ? activeBearHigh : swingStop;
   double stopBase = (swingStop - entry < minStopDistance) ? zoneStop : swingStop;
   double stop = stopBase + StopBufferPips * pip;
   return stop - entry;
}

//+------------------------------------------------------------------+
void ExecutePlan(const TradePlan &plan)
{
   Print(plan.entryName, " signal: lots=", DoubleToString(plan.lots, 2), " entry=", DoubleToString(plan.entry, DigitsForSymbol()), " sl=", DoubleToString(plan.stop, DigitsForSymbol()), " tp=", DoubleToString(plan.target, DigitsForSymbol()), " risk%=", DoubleToString(CurrentRiskPct(), 2));
   if(!EnableTrading)
   {
      Print("EnableTrading=false. Signal logged only, no order sent.");
      return;
   }

   bool ok = false;
   double ask = SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(TradeSymbol, SYMBOL_BID);
   if(plan.orderType == ORDER_TYPE_BUY)
   {
      if(plan.useLimit && plan.entry < ask)
         ok = trade.BuyLimit(plan.lots, plan.entry, TradeSymbol, plan.stop, plan.target, ORDER_TIME_GTC, 0, plan.entryName);
      else
         ok = trade.Buy(plan.lots, TradeSymbol, 0.0, plan.stop, plan.target, plan.entryName);
   }
   else
   {
      if(plan.useLimit && plan.entry > bid)
         ok = trade.SellLimit(plan.lots, plan.entry, TradeSymbol, plan.stop, plan.target, ORDER_TIME_GTC, 0, plan.entryName);
      else
         ok = trade.Sell(plan.lots, TradeSymbol, 0.0, plan.stop, plan.target, plan.entryName);
   }

   if(ok)
   {
      partialClosed = false;
      activeEntryName = plan.entryName;
      activeInitialStop = plan.stop;
      activeRisk = plan.riskDistance;
   }
   else
      Print("Order failed. Retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(CloseOnLimitBreach && UsePropGuard && (CurrentDailyDdPct() >= DailyDdLimitPct || CurrentTotalDdPct() >= TotalDdLimitPct))
      CloseOwnPositions("Prop limit breach");

   if(!HasOpenPosition())
   {
      partialClosed = false;
      activeEntryName = "";
      activeInitialStop = 0.0;
      activeRisk = 0.0;
      return;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != TradeSymbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0.0 || tp <= 0.0)
         continue;

      double risk = activeRisk > PointSize() ? activeRisk : (type == POSITION_TYPE_BUY ? openPrice - sl : sl - openPrice);
      if(risk <= PointSize())
         continue;

      if(UsePartialTakeProfitActive() && !partialClosed)
      {
         double partialPrice = type == POSITION_TYPE_BUY ? openPrice + risk * PartialTpRActive() : openPrice - risk * PartialTpRActive();
         double now = type == POSITION_TYPE_BUY ? SymbolInfoDouble(TradeSymbol, SYMBOL_BID) : SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
         bool hit = type == POSITION_TYPE_BUY ? now >= partialPrice : now <= partialPrice;
         if(hit)
         {
            double closeLots = NormalizeLots(volume * PartialQtyPct / 100.0);
            double minLot = SymbolInfoDouble(TradeSymbol, SYMBOL_VOLUME_MIN);
            if(closeLots >= minLot && closeLots < volume)
               partialClosed = trade.PositionClosePartial(ticket, closeLots);
            else
               partialClosed = true;
         }
      }

      if(UseBreakEvenActive())
      {
         double trigger = type == POSITION_TYPE_BUY ? openPrice + risk * BreakEvenAtRActive() : openPrice - risk * BreakEvenAtRActive();
         double newSl = type == POSITION_TYPE_BUY ? openPrice + risk * BreakEvenPlusRActive() : openPrice - risk * BreakEvenPlusRActive();
         double now = type == POSITION_TYPE_BUY ? SymbolInfoDouble(TradeSymbol, SYMBOL_BID) : SymbolInfoDouble(TradeSymbol, SYMBOL_ASK);
         bool shouldMove = type == POSITION_TYPE_BUY ? (now >= trigger && sl < newSl) : (now <= trigger && sl > newSl);
         if(shouldMove)
            trade.PositionModify(ticket, NormalizePrice(newSl), tp);
      }
   }
}

//+------------------------------------------------------------------+
void UpdateAsiaLondonState(const MqlRates &m15[])
{
   int hour = EntryHour(m15[1].time);
   if(hour >= AsiaStartHour && hour < AsiaEndHour)
   {
      asiaLow = hasAsiaLow ? MathMin(asiaLow, m15[1].low) : m15[1].low;
      asiaHigh = hasAsiaHigh ? MathMax(asiaHigh, m15[1].high) : m15[1].high;
      hasAsiaLow = true;
      hasAsiaHigh = true;
      londonBullNightTest = londonBullNightTest || (hasActiveBullZone && m15[1].low <= activeBullHigh && m15[1].high >= activeBullLow);
      londonBearNightTest = londonBearNightTest || (hasActiveBearZone && m15[1].high >= activeBearLow && m15[1].low <= activeBearHigh);
   }
}

void UpdateRangeInvalidation(const MqlRates &h4[], bool h4NewBar)
{
   if(!h4NewBar)
      return;
   double rangeHigh, rangeLow, rangeAtr;
   if(!GetH4Range(h4, rangeHigh, rangeLow, rangeAtr))
      return;
   rangeClosesAbove = h4[1].close > rangeHigh ? rangeClosesAbove + 1 : 0;
   rangeClosesBelow = h4[1].close < rangeLow ? rangeClosesBelow + 1 : 0;
}

//+------------------------------------------------------------------+
bool IsNewBullFvg15(const MqlRates &m15[]) { return m15[1].low > m15[3].high; }
bool IsNewBearFvg15(const MqlRates &m15[]) { return m15[1].high < m15[3].low; }
bool IsIfvgUp(const MqlRates &m15[]) { return hasLastBearFvg15 && m15[1].close > lastBearFvgHigh15 && m15[2].close <= lastBearFvgHigh15; }
bool IsIfvgDown(const MqlRates &m15[]) { return hasLastBullFvg15 && m15[1].close < lastBullFvgLow15 && m15[2].close >= lastBullFvgLow15; }

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

bool IsBosUp(const MqlRates &m15[]) { return hasLastSwingHigh && m15[1].close > lastSwingHigh && m15[2].close <= lastSwingHigh; }
bool IsBosDown(const MqlRates &m15[]) { return hasLastSwingLow && m15[1].close < lastSwingLow && m15[2].close >= lastSwingLow; }
bool ConfirmationStrong(const MqlRates &m15[])
{
   if(MinConfirmationAtr <= 0.0)
      return true;
   double atr = Atr(m15, 14, 1);
   return atr > 0.0 && MathAbs(m15[1].close - m15[1].open) >= atr * MinConfirmationAtr;
}

//+------------------------------------------------------------------+
bool CanOpenNewTrade()
{
   datetime now = AdjustedTime(TimeCurrent());
   if(now < BacktestStart || now > BacktestEnd)
      return false;
   if(HasOpenPosition() || HasOwnPendingOrders())
      return false;
   if(!InEntrySession(TimeCurrent()))
      return false;
   if(!PropTradingAllowed())
      return false;
   if(dailyLossCount >= MaxDailyLossesActive())
      return false;
   return true;
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == TradeSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

bool HasOwnPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket != 0 && OrderGetString(ORDER_SYMBOL) == TradeSymbol && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void UpdatePropGuard()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   datetime dayStart = DayStart(AdjustedTime(TimeCurrent()));
   if(dayStart != currentDayStart)
   {
      currentDayStart = dayStart;
      dayEquityPeak = equity;
      dailyTradingLocked = false;
      dailyLossCount = 0;
      hasAsiaLow = false;
      hasAsiaHigh = false;
      londonBullNightTest = false;
      londonBearNightTest = false;
      londonTradeTaken = false;
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
   if(UsePropGuard && totalPct >= TotalLockBufferPctActive())
      totalTradingLocked = true;
}

bool PropTradingAllowed()
{
   if(!UsePropGuard)
      return true;
   return !dailyTradingLocked && !totalTradingLocked && CurrentDailyDdPct() < DailyDdLimitPct && CurrentTotalDdPct() < TotalDdLimitPct;
}

double CurrentRiskPct()
{
   double totalDd = CurrentTotalDdPct();
   if(UsePropGuard && UseDynamicRisk && totalDd >= DdLevel2Pct)
      return MathMin(RiskAtLevel2PctActive(), RiskPerTradePctActive());
   if(UsePropGuard && UseDynamicRisk && totalDd >= DdLevel1Pct)
      return MathMin(RiskAtLevel1PctActive(), RiskPerTradePctActive());
   return RiskPerTradePctActive();
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

void InitializeLastProcessedCloseDeal()
{
   if(!HistorySelect(0, TimeCurrent()))
      return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal != 0 && IsOwnCloseDeal(deal))
      {
         lastProcessedCloseDeal = deal;
         return;
      }
   }
}

void UpdateDailyLossCount()
{
   if(!HistorySelect(DayStart(TimeCurrent()), TimeCurrent()))
      return;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || deal <= lastProcessedCloseDeal || !IsOwnCloseDeal(deal))
         continue;
      double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + HistoryDealGetDouble(deal, DEAL_COMMISSION);
      if(profit < 0.0)
      {
         dailyLossCount++;
         string comment = HistoryDealGetString(deal, DEAL_COMMENT);
         if(UseControlledReentryActive() && StringFind(comment, "Long") >= 0 && bullZoneReentries < MaxReentriesPerZone && hasActiveBullZone)
         {
            bullZoneReentries++;
            bullZoneTraded = false;
            bullZoneTested = false;
            bullBarsAfterTest = 100000;
         }
         if(UseControlledReentryActive() && StringFind(comment, "Short") >= 0 && bearZoneReentries < MaxReentriesPerZone && hasActiveBearZone)
         {
            bearZoneReentries++;
            bearZoneTraded = false;
            bearZoneTested = false;
            bearBarsAfterTest = 100000;
         }
      }
      lastProcessedCloseDeal = deal;
   }
}

bool IsOwnCloseDeal(ulong deal)
{
   return HistoryDealGetString(deal, DEAL_SYMBOL) == TradeSymbol && HistoryDealGetInteger(deal, DEAL_MAGIC) == MagicNumber && HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_OUT;
}

void CloseOwnPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == TradeSymbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         Print("Closing position: ", reason);
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
bool IsH4BullBias()
{
   double fast[], slow[], closes[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(closes, true);
   if(CopyBuffer(fastEmaHandle, 0, 1, 1, fast) < 1 || CopyBuffer(slowEmaHandle, 0, 1, 1, slow) < 1 || CopyClose(TradeSymbol, PERIOD_H4, 1, 1, closes) < 1)
      return false;
   return closes[0] > fast[0] && fast[0] > slow[0];
}

bool IsH4BearBias()
{
   double fast[], slow[], closes[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(closes, true);
   if(CopyBuffer(fastEmaHandle, 0, 1, 1, fast) < 1 || CopyBuffer(slowEmaHandle, 0, 1, 1, slow) < 1 || CopyClose(TradeSymbol, PERIOD_H4, 1, 1, closes) < 1)
      return false;
   return closes[0] < fast[0] && fast[0] < slow[0];
}

//+------------------------------------------------------------------+
bool GetH4Range(const MqlRates &h4[], double &rangeHigh, double &rangeLow, double &rangeAtr)
{
   rangeHigh = HighestHigh(h4, RangeLookbackHtf, 1);
   rangeLow = LowestLow(h4, RangeLookbackHtf, 1);
   rangeAtr = Atr(h4, RangeAtrLen, 1);
   return rangeHigh > rangeLow && rangeAtr > 0.0;
}

double RangeTargetPrice(bool isLong, double oppositeBoundary, double mid, int quality)
{
   if(RangeTarget == RangeTargetMidline)
      return mid;
   if(RangeTarget == RangeTargetOppositeBoundary)
      return oppositeBoundary;
   return quality >= HighQualityTargetScore ? oppositeBoundary : mid;
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

double Atr(const MqlRates &rates[], int len, int startIndex)
{
   double sum = 0.0;
   for(int i = startIndex; i < startIndex + len; i++)
   {
      double prevClose = rates[i + 1].close;
      double tr = MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - prevClose), MathAbs(rates[i].low - prevClose)));
      sum += tr;
   }
   return sum / len;
}

//+------------------------------------------------------------------+
double CalculateLots(double riskDistance, double riskPct)
{
   double riskCash = AccountInfoDouble(ACCOUNT_EQUITY) * riskPct / 100.0;
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

double NormalizePrice(double price) { return NormalizeDouble(price, DigitsForSymbol()); }
int DigitsForSymbol() { return (int)SymbolInfoInteger(TradeSymbol, SYMBOL_DIGITS); }
double PointSize() { return SymbolInfoDouble(TradeSymbol, SYMBOL_POINT); }
double PipSize()
{
   int digits = DigitsForSymbol();
   double point = PointSize();
   return digits == 3 || digits == 5 ? point * 10.0 : point;
}

bool IsNewM15Bar()
{
   datetime t = iTime(TradeSymbol, PERIOD_M15, 0);
   if(t == 0 || t == lastM15BarTime)
      return false;
   lastM15BarTime = t;
   return true;
}

datetime AdjustedTime(datetime t) { return t + EntryHourOffset * 3600; }
datetime DayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

int EntryHour(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(AdjustedTime(t), dt);
   return dt.hour;
}

bool InEntrySession(datetime t)
{
   int hour = EntryHour(t);
   if(UseNoEntryAfterHour && hour >= NoEntryAfterHour)
      return false;
   if(UseSessionFilter && (hour < SessionStartHour || hour >= SessionEndHour))
      return false;
   return true;
}

bool IsInBacktestWindow(datetime t)
{
   datetime adjusted = AdjustedTime(t);
   return adjusted >= BacktestStart && adjusted <= BacktestEnd;
}

bool IsEurUsd() { return StringFind(TradeSymbol, "EURUSD") >= 0; }
bool AllowLongDirection() { return TradeDirection == DirectionBoth || TradeDirection == DirectionLongOnly; }
bool AllowShortDirection() { return TradeDirection == DirectionBoth || TradeDirection == DirectionShortOnly; }

//+------------------------------------------------------------------+
bool IsCustom() { return ExecutionProfile == ProfileCustom; }
bool IsPropPass45() { return ExecutionProfile == ProfilePropPass45; }
bool IsAggressive() { return ExecutionProfile == ProfileAggressive; }
double RRActive() { return IsCustom() ? RR : (IsPropPass45() ? 2.0 : ExecutionProfile == ProfilePropConservative ? 2.0 : ExecutionProfile == ProfilePropBalanced ? 2.5 : 3.0); }
int MinQualityScoreActive() { return IsCustom() ? MinQualityScore : (IsPropPass45() ? 5 : ExecutionProfile == ProfilePropConservative ? 5 : ExecutionProfile == ProfilePropBalanced ? 4 : ExecutionProfile == ProfilePropGrowth ? 5 : 2); }
bool UseStrictConfirmationActive() { return IsCustom() ? UseStrictConfirmation : IsPropPass45(); }
bool UseHtfBiasActive() { return IsCustom() ? UseHtfBias : UseHtfBias; }
bool UseFtaFilterActive() { return IsCustom() ? UseFtaFilter : true; }
bool UsePullbackLimitEntryActive() { return IsCustom() ? UsePullbackLimitEntry : false; }
bool UseBreakEvenActive() { return IsCustom() ? UseBreakEven : true; }
double BreakEvenAtRActive() { return IsCustom() ? BreakEvenAtR : 1.0; }
double BreakEvenPlusRActive() { return IsCustom() ? BreakEvenPlusR : 0.0; }
bool UsePartialTakeProfitActive() { return IsCustom() ? UsePartialTakeProfit : false; }
double PartialTpRActive() { return IsCustom() ? PartialTpR : 2.0; }
double RunnerTpRActive() { return IsCustom() ? RunnerTpR : (ExecutionProfile == ProfilePropGrowth ? 3.5 : RRActive()); }
double RiskPerTradePctActive() { return IsCustom() ? RiskPerTradePct : (IsPropPass45() ? 0.5 : ExecutionProfile == ProfilePropConservative ? 0.5 : ExecutionProfile == ProfilePropBalanced ? 0.75 : ExecutionProfile == ProfilePropGrowth ? 1.5 : RiskPerTradePct); }
bool UseControlledReentryActive() { return IsCustom() ? UseControlledReentry : (IsAggressive() && UseControlledReentry); }
bool UseAdaptiveTargetsActive() { return IsCustom() ? UseAdaptiveTargets : true; }
double RiskAtLevel1PctActive() { return IsCustom() ? RiskAtLevel1Pct : (IsPropPass45() ? 0.25 : ExecutionProfile == ProfilePropBalanced ? 0.5 : ExecutionProfile == ProfilePropGrowth ? 1.0 : RiskAtLevel1Pct); }
double RiskAtLevel2PctActive() { return IsCustom() ? RiskAtLevel2Pct : (IsPropPass45() ? 0.10 : ExecutionProfile == ProfilePropGrowth ? 0.5 : RiskAtLevel2Pct); }
double TotalLockBufferPctActive() { return IsCustom() ? TotalLockBufferPct : (ExecutionProfile == ProfilePropGrowth ? 9.5 : TotalLockBufferPct); }
int MaxDailyLossesActive() { return IsPropPass45() ? 1 : IsAggressive() ? MaxDailyLosses : MathMin(MaxDailyLosses, 2); }

//+------------------------------------------------------------------+
void UpdatePanel()
{
   string text = "EURUSD Playbook FVG Strategy Current MT5\n";
   text += "EnableTrading: " + BoolText(EnableTrading) + " | Profile: " + ProfileText() + " | Last: " + lastSignal + "\n";
   text += "Risk now: " + DoubleToString(CurrentRiskPct(), 2) + "% | RR: " + DoubleToString(RRActive(), 2) + " | BE: " + BoolText(UseBreakEvenActive()) + " | Partial: " + BoolText(UsePartialTakeProfitActive()) + "\n";
   text += "Daily DD: " + DoubleToString(CurrentDailyDdPct(), 2) + "% / max " + DoubleToString(maxDailyDrawdownPct, 2) + "% | losses: " + IntegerToString(dailyLossCount) + "\n";
   text += "Total DD: " + DoubleToString(CurrentTotalDdPct(), 2) + "% / max " + DoubleToString(maxTotalDrawdownPct, 2) + "% | Prop: " + BoolText(PropTradingAllowed()) + "\n";
   text += "Bull zone: " + ZoneText(hasActiveBullZone, activeBullLow, activeBullHigh) + " age=" + IntegerToString(bullZoneAge) + " tested=" + BoolText(bullZoneTested) + " traded=" + BoolText(bullZoneTraded) + " re=" + IntegerToString(bullZoneReentries) + "\n";
   text += "Bear zone: " + ZoneText(hasActiveBearZone, activeBearLow, activeBearHigh) + " age=" + IntegerToString(bearZoneAge) + " tested=" + BoolText(bearZoneTested) + " traded=" + BoolText(bearZoneTraded) + " re=" + IntegerToString(bearZoneReentries) + "\n";
   text += "Range module: " + BoolText(UseRangeModule) + " | London: " + BoolText(UseLondonOpenSetup) + " | Offset: " + IntegerToString(EntryHourOffset) + "h";
   Comment(text);
}

string BoolText(bool value) { return value ? "Yes" : "No"; }
string ZoneText(bool active, double low, double high)
{
   if(!active)
      return "None";
   return DoubleToString(low, DigitsForSymbol()) + " - " + DoubleToString(high, DigitsForSymbol());
}
string ProfileText()
{
   if(ExecutionProfile == ProfilePropPass45)
      return "Prop Pass 45";
   if(ExecutionProfile == ProfilePropConservative)
      return "Prop Conservative";
   if(ExecutionProfile == ProfilePropBalanced)
      return "Prop Balanced";
   if(ExecutionProfile == ProfilePropGrowth)
      return "Prop Growth";
   if(ExecutionProfile == ProfileAggressive)
      return "Aggressive";
   return "Custom";
}
//+------------------------------------------------------------------+
