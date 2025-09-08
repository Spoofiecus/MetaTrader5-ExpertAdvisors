//+------------------------------------------------------------------+
//|                                  PriceActionRetracement.mq5 |
//|                        Copyright 2023, Your Name |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name"
#property link      "https.mql5.com"
#property version   "1.00"
#property description "EURUSD 1-Min Pure Price Action Retracement Strategy"

#include <Trade/Trade.mqh>

//--- Enums for cleaner code
enum ENUM_TREND
  {
   TREND_UP,
   TREND_DOWN,
   TREND_NONE
  };

//--- Struct to hold pattern information
struct PatternInfo
  {
   string name;          // Name of the pattern found, e.g., "Bullish PinBar"
   double sl_base_price; // The price level to base the SL on
   double tp_base_price; // The price level to base the TP on (e.g., high of signal candle)
  };

//--- Input Parameters
input double          RiskPercent = 1.0;            // Risk percentage per trade
input double          RiskRewardRatio = 2.0;        // Risk-to-Reward Ratio (e.g., 2.0 for 1:2)
input double          DailyLossLimitPercent = 5.0;  // Stop trading if daily loss exceeds this %
input ulong           MagicNumber = 12345;          // EA's magic number
input int             MaxTradesPerSession = 5;      // Maximum trades per session
input int             Slippage = 3;                 // Slippage in points
input int             Lookback5M = 50;              // Bars to check for 5-min trend
input int             Lookback1M = 100;             // Bars to check for 1-min S/R
input double          SRZonePips = 3.0;             // S/R zone thickness in pips
input int             ConsolidationMaxPips = 15;    // Max height of consolidation range in pips
input bool            EnableEngulfing = true;       // Toggle for Engulfing patterns
input bool            EnablePinBars = true;         // Toggle for Pin Bar patterns
input bool            EnableTwoCandleReversal = true; // Toggle for Two-Candle Reversal patterns
input bool            EnableWickCluster = true;     // Toggle for Rejection Wick Cluster patterns
input bool            EnableConsolidationBreakout = true; // Toggle for Consolidation Breakout patterns

//--- Global variables
CTrade trade;
int    tradesToday = 0;
double dailyLoss = 0.0; // as a percentage
datetime newDay;
double startOfDayBalance = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);

//--- Initialize daily counters
   newDay = iTime(_Symbol, PERIOD_D1, 0);
   startOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("EA Initialized. Magic Number: ", MagicNumber);
   Print("Risk/Reward: 1:", RiskRewardRatio, " | Risk per trade: ", RiskPercent, "%");
   Print("Daily Loss Limit: ", DailyLossLimitPercent, "% | Max Trades: ", MaxTradesPerSession);
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   Print("EA Deinitialized. Reason: ", reason);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- New bar check
   static datetime lastBarTime = 0;
   if(iTime(_Symbol, PERIOD_M1, 0) == lastBarTime)
      return;
   lastBarTime = iTime(_Symbol, PERIOD_M1, 0);

//--- Daily counters check
   if(iTime(_Symbol, PERIOD_D1, 0) != newDay)
     {
      tradesToday = 0;
      dailyLoss = 0.0;
      newDay = iTime(_Symbol, PERIOD_D1, 0);
      startOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("New day started. Counters reset.");
     }

//--- Check if trading is allowed (no open positions for this magic number)
   if(PositionSelect(_Symbol))
     {
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return; // EA already has a position, wait.
     }

//--- Update and check trading session limits
   UpdateDailyCounters();
   if(tradesToday >= MaxTradesPerSession)
     {
      //Print("Max trades for the session reached.");
      return;
     }
   if(DailyLossLimitPercent > 0 && dailyLoss >= DailyLossLimitPercent)
     {
      //Print("Daily loss limit reached.");
      return;
     }

//--- Get all necessary data for the current tick
   MqlRates rates1M[];
   if(CopyRates(_Symbol, PERIOD_M1, 0, 10, rates1M) < 10) return;
   ArraySetAsSeries(rates1M, true);

   ENUM_TREND trend = GetTrendM5();
   double support = GetNearestSupport();
   double resistance = GetNearestResistance();
   PatternInfo pattern = GetCandlestickPattern(rates1M, 1); // Check on last closed bar

//--- Main Strategy Logic
   if(pattern.name != "NONE")
     {
      // Bullish setup validation
      if(trend == TREND_UP && StringFind(pattern.name, "Bullish") != -1 && support > 0)
        {
         // Check if the base of the pattern is near the support level
         if(MathAbs(pattern.sl_base_price - support) <= SRZonePips * _Point)
           {
            Print("BUY SIGNAL: Trend is UP, ", pattern.name, " found near support ", NormalizeDouble(support, _Digits));
            ExecuteBuy(pattern.sl_base_price, pattern.tp_base_price);
           }
        }
      // Bearish setup validation
      else if(trend == TREND_DOWN && StringFind(pattern.name, "Bearish") != -1 && resistance > 0)
        {
         // Check if the base of the pattern is near the resistance level
         if(MathAbs(pattern.sl_base_price - resistance) <= SRZonePips * _Point)
           {
            Print("SELL SIGNAL: Trend is DOWN, ", pattern.name, " found near resistance ", NormalizeDouble(resistance, _Digits));
            ExecuteSell(pattern.sl_base_price, pattern.tp_base_price);
           }
        }
     }
  }
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Trade Execution and Risk Management                              |
//+------------------------------------------------------------------+
void ExecuteBuy(double sl_base, double tp_base)
  {
   double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   // Add a 2-pip buffer. Assumes 1 pip = 10 points for a 5-digit broker.
   double sl_price = sl_base - (2 * 10 * _Point);

   if(sl_price >= entry_price)
     {
      Print("Invalid SL for Buy (would trigger instantly). Aborting.");
      return;
     }

   double sl_pips = (entry_price - sl_price) / (10 * _Point);
   if(sl_pips < 3 || sl_pips > 100)
     {
      Print("SL pips (", sl_pips, ") out of range [3, 100]. Aborting.");
      return;
     }

   double tp_price = entry_price + (sl_pips * RiskRewardRatio * _Point * 10);
   double lots = CalculateLotSize(sl_pips);

   if(lots <= 0)
     {
      Print("Calculated lot size is invalid (<= 0). Aborting.");
      return;
     }

   if(!trade.Buy(lots, _Symbol, entry_price, sl_price, tp_price, "PA Retracement EA"))
     {
      Print("Buy order failed: ", GetLastError());
     }
   else
     {
      Print("BUY executed: ", lots, " lots, SL=", sl_price, ", TP=", tp_price);
      UpdateDailyCounters(); // Recalculate counters after trade
     }
  }

void ExecuteSell(double sl_base, double tp_base)
  {
   double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // Add a 2-pip buffer. Assumes 1 pip = 10 points for a 5-digit broker.
   double sl_price = sl_base + (2 * 10 * _Point);

   if(sl_price <= entry_price)
     {
      Print("Invalid SL for Sell (would trigger instantly). Aborting.");
      return;
     }

   double sl_pips = (sl_price - entry_price) / (10 * _Point);
   if(sl_pips < 3 || sl_pips > 100)
     {
      Print("SL pips (", sl_pips, ") out of range [3, 100]. Aborting.");
      return;
     }

   double tp_price = entry_price - (sl_pips * RiskRewardRatio * _Point * 10);
   double lots = CalculateLotSize(sl_pips);

   if(lots <= 0)
     {
      Print("Calculated lot size is invalid (<= 0). Aborting.");
      return;
     }

   if(!trade.Sell(lots, _Symbol, entry_price, sl_price, tp_price, "PA Retracement EA"))
     {
      Print("Sell order failed: ", GetLastError());
     }
   else
     {
      Print("SELL executed: ", lots, " lots, SL=", sl_price, ", TP=", tp_price);
      UpdateDailyCounters(); // Recalculate counters after trade
     }
  }

double CalculateLotSize(double stop_loss_pips)
  {
   if(stop_loss_pips <= 0 || RiskPercent <= 0) return 0.0;

   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (RiskPercent / 100.0);

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0) return 0.0;

   double value_per_point = tick_value / tick_size * _Point;
   double sl_points = stop_loss_pips * 10;
   double loss_for_one_lot = sl_points * value_per_point;
   if(loss_for_one_lot <= 0) return 0.0;

   double lots = risk_amount / loss_for_one_lot;

   // Normalize and clamp lot size
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lot_step) * lot_step;

   if(lots < min_lot) return 0.0; // Abort if too small
   if(lots > max_lot) lots = max_lot;

   return NormalizeDouble(lots, 2);
  }

void UpdateDailyCounters()
  {
   if(startOfDayBalance == 0) startOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(!HistorySelect(newDay, TimeCurrent()))
     {
      Print("Could not select history: ", GetLastError());
      return;
     }

   int deals = HistoryDealsTotal();
   int trades_count = 0;
   double profit_loss = 0;

   for(int i = 0; i < deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber)
        {
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            trades_count++;
           }
         profit_loss += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         profit_loss += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         profit_loss += HistoryDealGetDouble(ticket, DEAL_SWAP);
        }
     }
   tradesToday = trades_count;

   if(startOfDayBalance > 0 && profit_loss < 0)
     {
      dailyLoss = (-profit_loss / startOfDayBalance) * 100.0;
     }
   else
     {
      dailyLoss = 0;
     }
  }

//+------------------------------------------------------------------+
//| Core Helper Functions                                            |
//+------------------------------------------------------------------+

//--- Determines trend on the 5-minute chart
ENUM_TREND GetTrendM5()
  {
//--- Find last two major swing highs and lows by splitting the lookback period
   int high1_idx_shift = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, Lookback5M / 2, 1);
   int high2_idx_shift = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, Lookback5M - (Lookback5M / 2), Lookback5M / 2);

   int low1_idx_shift = iLowest(_Symbol, PERIOD_M5, MODE_LOW, Lookback5M / 2, 1);
   int low2_idx_shift = iLowest(_Symbol, PERIOD_M5, MODE_LOW, Lookback5M - (Lookback5M / 2), Lookback5M / 2);

   //--- Error check for swing points
   if(high1_idx_shift < 0 || high2_idx_shift < 0 || low1_idx_shift < 0 || low2_idx_shift < 0)
     {
      Print("Could not identify swing points for M5 trend analysis.");
      return(TREND_NONE);
     }

   //--- Get the price levels of the swing points
   double high1 = iHigh(_Symbol, PERIOD_M5, high1_idx_shift);
   double high2 = iHigh(_Symbol, PERIOD_M5, high2_idx_shift);
   double low1 = iLow(_Symbol, PERIOD_M5, low1_idx_shift);
   double low2 = iLow(_Symbol, PERIOD_M5, low2_idx_shift);

//--- Check for trend
   if(high1 > high2 && low1 > low2)
      return(TREND_UP);
   if(high1 < high2 && low1 < low2)
      return(TREND_DOWN);

   return(TREND_NONE);
  }

//--- Finds the nearest support level on the 1-minute chart
double GetNearestSupport()
  {
   MqlRates rates1M[];
   if(CopyRates(_Symbol, PERIOD_M1, 1, Lookback1M, rates1M) < Lookback1M)
     {
      Print("Error: Could not get M1 historical data for support. ", GetLastError());
      return(0.0);
     }
   ArraySetAsSeries(rates1M, true); // rates1M[0] is the most recent closed bar (shift=1)

   double current_low = iLow(_Symbol, PERIOD_M1, 1);
   double nearest_support = 0.0;

//--- Find swing lows (a low with higher lows on both sides)
   for(int i = 2; i < Lookback1M - 2; i++)
     {
      if(rates1M[i].low < rates1M[i - 1].low && rates1M[i].low < rates1M[i - 2].low &&
         rates1M[i].low < rates1M[i + 1].low && rates1M[i].low < rates1M[i + 2].low)
        {
         double swing_low = rates1M[i].low;
         if(swing_low < current_low)
           {
            if(nearest_support == 0.0 || swing_low > nearest_support)
              {
               nearest_support = swing_low;
              }
           }
        }
     }
   return(nearest_support);
  }

//--- Finds the nearest resistance level on the 1-minute chart
double GetNearestResistance()
  {
   MqlRates rates1M[];
   if(CopyRates(_Symbol, PERIOD_M1, 1, Lookback1M, rates1M) < Lookback1M)
     {
      Print("Error: Could not get M1 historical data for resistance. ", GetLastError());
      return(0.0);
     }
   ArraySetAsSeries(rates1M, true); // rates1M[0] is the most recent closed bar (shift=1)

   double current_high = iHigh(_Symbol, PERIOD_M1, 1);
   double nearest_resistance = 0.0;

//--- Find swing highs (a high with lower highs on both sides)
   for(int i = 2; i < Lookback1M - 2; i++)
     {
      if(rates1M[i].high > rates1M[i - 1].high && rates1M[i].high > rates1M[i - 2].high &&
         rates1M[i].high > rates1M[i + 1].high && rates1M[i].high > rates1M[i + 2].high)
        {
         double swing_high = rates1M[i].high;
         if(swing_high > current_high)
           {
            if(nearest_resistance == 0.0 || swing_high < nearest_resistance)
              {
               nearest_resistance = swing_high;
              }
           }
        }
     }
   return(nearest_resistance);
  }

//+------------------------------------------------------------------+
//| Candlestick Pattern Functions                                    |
//+------------------------------------------------------------------+

//--- Checks for any valid candlestick pattern at the given shift
PatternInfo GetCandlestickPattern(const MqlRates &rates[], int shift)
  {
   PatternInfo result;
   result.name = "NONE";

   if(EnableEngulfing)
     {
      if(IsBullishEngulfing(rates, shift))
        {
         result.name = "Bullish Engulfing";
         result.sl_base_price = rates[shift].low;
         result.tp_base_price = rates[shift].high;
         return result;
        }
      if(IsBearishEngulfing(rates, shift))
        {
         result.name = "Bearish Engulfing";
         result.sl_base_price = rates[shift].high;
         result.tp_base_price = rates[shift].low;
         return result;
        }
     }
   if(EnablePinBars)
     {
      if(IsBullishPinBar(rates, shift))
        {
         result.name = "Bullish PinBar";
         result.sl_base_price = rates[shift].low;
         result.tp_base_price = rates[shift].high;
         return result;
        }
      if(IsBearishPinBar(rates, shift))
        {
         result.name = "Bearish PinBar";
         result.sl_base_price = rates[shift].high;
         result.tp_base_price = rates[shift].low;
         return result;
        }
     }
   if(EnableTwoCandleReversal)
     {
      if(IsTwoCandleReversalBullish(rates, shift))
        {
         result.name = "Bullish Two-Candle Reversal";
         result.sl_base_price = rates[shift+1].low; // SL is below the first candle's low
         result.tp_base_price = rates[shift].high;
         return result;
        }
      if(IsTwoCandleReversalBearish(rates, shift))
        {
         result.name = "Bearish Two-Candle Reversal";
         result.sl_base_price = rates[shift+1].high; // SL is above the first candle's high
         result.tp_base_price = rates[shift].low;
         return result;
        }
     }

   //--- New pattern checks for Wick Cluster
   if(EnableWickCluster)
     {
      double sl_price = 0;
      if(IsBullishWickCluster(rates, shift, 3, sl_price)) // Check for 3-candle cluster
        {
         result.name = "Bullish Wick Cluster";
         result.sl_base_price = sl_price;
         result.tp_base_price = rates[shift].high; // TP base is high of last candle in cluster
         return result;
        }
      if(IsBearishWickCluster(rates, shift, 3, sl_price))
        {
         result.name = "Bearish Wick Cluster";
         result.sl_base_price = sl_price;
         result.tp_base_price = rates[shift].low;
         return result;
        }
     }

   //--- New pattern checks for Consolidation Breakout
   if(EnableConsolidationBreakout)
     {
      double sl_price = 0, tp_price = 0;
      if(IsConsolidationBreakoutBullish(rates, shift, 4, sl_price, tp_price)) // 4-candle consolidation
        {
         result.name = "Bullish Consolidation Breakout";
         result.sl_base_price = sl_price;
         result.tp_base_price = tp_price;
         return result;
        }
      if(IsConsolidationBreakoutBearish(rates, shift, 4, sl_price, tp_price))
        {
         result.name = "Bearish Consolidation Breakout";
         result.sl_base_price = sl_price;
         result.tp_base_price = tp_price;
         return result;
        }
     }

   return result;
  }

//--- Checks for a Bullish Engulfing pattern
bool IsBullishEngulfing(const MqlRates &rates[], int shift)
  {
   if(shift + 1 >= ArraySize(rates)) return false;
   bool prev_is_bearish = rates[shift+1].close < rates[shift+1].open;
   bool curr_is_bullish = rates[shift].close > rates[shift].open;
   bool engulfs = rates[shift].close > rates[shift+1].open && rates[shift].open < rates[shift+1].close;
   return prev_is_bearish && curr_is_bullish && engulfs;
  }

//--- Checks for a Bearish Engulfing pattern
bool IsBearishEngulfing(const MqlRates &rates[], int shift)
  {
   if(shift + 1 >= ArraySize(rates)) return false;
   bool prev_is_bullish = rates[shift+1].close > rates[shift+1].open;
   bool curr_is_bearish = rates[shift].close < rates[shift].open;
   bool engulfs = rates[shift].open > rates[shift+1].close && rates[shift].close < rates[shift+1].open;
   return prev_is_bullish && curr_is_bearish && engulfs;
  }

//--- Checks for a Bullish Pin Bar pattern
bool IsBullishPinBar(const MqlRates &rates[], int shift)
  {
   double range = rates[shift].high - rates[shift].low;
   if(range == 0) return false;
   double body = MathAbs(rates[shift].open - rates[shift].close);
   double lower_wick = MathMin(rates[shift].open, rates[shift].close) - rates[shift].low;
   bool small_body = body < range * 0.34;
   bool long_lower_wick = lower_wick > range * 0.6;
   return small_body && long_lower_wick;
  }

//--- Checks for a Bearish Pin Bar pattern
bool IsBearishPinBar(const MqlRates &rates[], int shift)
  {
   double range = rates[shift].high - rates[shift].low;
   if(range == 0) return false;
   double body = MathAbs(rates[shift].open - rates[shift].close);
   double upper_wick = rates[shift].high - MathMax(rates[shift].open, rates[shift].close);
   bool small_body = body < range * 0.34;
   bool long_upper_wick = upper_wick > range * 0.6;
   return small_body && long_upper_wick;
  }

//--- Checks for a Bullish Two-Candle Reversal
bool IsTwoCandleReversalBullish(const MqlRates &rates[], int shift)
  {
   if(shift + 1 >= ArraySize(rates)) return false;
   bool prev_is_bearish = rates[shift+1].close < rates[shift+1].open;
   bool curr_is_bullish = rates[shift].close > rates[shift].open;
   bool closes_above = rates[shift].close > rates[shift+1].high;
   return prev_is_bearish && curr_is_bullish && closes_above;
  }

//--- Checks for a Bearish Two-Candle Reversal
bool IsTwoCandleReversalBearish(const MqlRates &rates[], int shift)
  {
   if(shift + 1 >= ArraySize(rates)) return false;
   bool prev_is_bullish = rates[shift+1].close > rates[shift+1].open;
   bool curr_is_bearish = rates[shift].close < rates[shift].open;
   bool closes_below = rates[shift].close < rates[shift+1].low;
   return prev_is_bullish && curr_is_bearish && closes_below;
  }

//--- Checks for a Bullish Wick Cluster
bool IsBullishWickCluster(const MqlRates &rates[], int shift, int num_candles, double &sl_price)
  {
   // This function checks for a cluster of `num_candles` ending at the bar specified by `shift`.
   // The entry signal is the close of the `shift` bar itself. All data used is historical.
   if(shift + num_candles -1 >= ArraySize(rates)) return false;

   int rejection_count = 0;
   // Initialize with the first candle in the lookback period.
   double lowest_low = rates[shift].low;

   // Loop through the candles that form the potential cluster (e.g., bars at index 1, 2, 3)
   for(int i = shift; i < shift + num_candles; i++)
     {
      double range = rates[i].high - rates[i].low;
      if(range == 0) continue;

      // A bullish rejection candle has a long lower wick.
      double lower_wick = MathMin(rates[i].open, rates[i].close) - rates[i].low;
      if(lower_wick > range * 0.5)
        {
         rejection_count++;
        }

      // Find the lowest low within the cluster for SL placement.
      if(rates[i].low < lowest_low)
        {
         lowest_low = rates[i].low;
        }
     }

   // The strategy requires 2-3 candles. We check if at least 2 are rejection candles.
   if(rejection_count >= 2)
     {
      sl_price = lowest_low;
      return true;
     }
   return false;
  }

//--- Checks for a Bearish Wick Cluster
bool IsBearishWickCluster(const MqlRates &rates[], int shift, int num_candles, double &sl_price)
  {
   // This function checks for a cluster of `num_candles` ending at the bar specified by `shift`.
   if(shift + num_candles -1 >= ArraySize(rates)) return false;

   int rejection_count = 0;
   double highest_high = rates[shift].high;

   for(int i = shift; i < shift + num_candles; i++)
     {
      double range = rates[i].high - rates[i].low;
      if(range == 0) continue;

      double upper_wick = rates[i].high - MathMax(rates[i].open, rates[i].close);
      if(upper_wick > range * 0.5)
        {
         rejection_count++;
        }

      if(rates[i].high > highest_high)
        {
         highest_high = rates[i].high;
        }
     }

   if(rejection_count >= 2)
     {
      sl_price = highest_high;
      return true;
     }
   return false;
  }

//--- Checks for a Bullish Consolidation Breakout
bool IsConsolidationBreakoutBullish(const MqlRates &rates[], int breakout_candle_shift, int consolidation_length, double &sl_price, double &tp_price)
  {
   // This function checks for a breakout of a consolidation range.
   // The breakout candle is at `breakout_candle_shift` (e.g., 1).
   // The consolidation is the `consolidation_length` of bars *before* the breakout candle.
   if(breakout_candle_shift + consolidation_length >= ArraySize(rates)) return false;

   // --- Step 1: Identify the consolidation range boundaries ---
   int consolidation_start_shift = breakout_candle_shift + 1;
   int consolidation_end_shift = breakout_candle_shift + consolidation_length;
   double consolidation_high = 0, consolidation_low = 0;

   for(int i = consolidation_start_shift; i <= consolidation_end_shift; i++)
     {
      if(rates[i].high > consolidation_high || consolidation_high == 0) consolidation_high = rates[i].high;
      if(rates[i].low < consolidation_low || consolidation_low == 0) consolidation_low = rates[i].low;
     }

   // --- Step 2: Check if the consolidation range is "tight" enough ---
   if((consolidation_high - consolidation_low) > (ConsolidationMaxPips * 10 * _Point)) return false;

   // --- Step 3: Check if the breakout candle is valid ---
   MqlRates breakout_candle = rates[breakout_candle_shift];
   bool is_strong_bullish = breakout_candle.close > breakout_candle.open;
   double body = breakout_candle.close - breakout_candle.open;
   double range = breakout_candle.high - breakout_candle.low;

   if(is_strong_bullish && breakout_candle.close > consolidation_high && body > range * 0.4)
     {
      sl_price = consolidation_low;
      tp_price = breakout_candle.high;
      return true;
     }
   return false;
  }

//--- Checks for a Bearish Consolidation Breakout
bool IsConsolidationBreakoutBearish(const MqlRates &rates[], int breakout_candle_shift, int consolidation_length, double &sl_price, double &tp_price)
  {
   if(breakout_candle_shift + consolidation_length >= ArraySize(rates)) return false;

   int consolidation_start_shift = breakout_candle_shift + 1;
   int consolidation_end_shift = breakout_candle_shift + consolidation_length;
   double consolidation_high = 0, consolidation_low = 0;

   for(int i = consolidation_start_shift; i <= consolidation_end_shift; i++)
     {
      if(rates[i].high > consolidation_high || consolidation_high == 0) consolidation_high = rates[i].high;
      if(rates[i].low < consolidation_low || consolidation_low == 0) consolidation_low = rates[i].low;
     }

   if((consolidation_high - consolidation_low) > (ConsolidationMaxPips * 10 * _Point)) return false;

   MqlRates breakout_candle = rates[breakout_candle_shift];
   bool is_strong_bearish = breakout_candle.close < breakout_candle.open;
   double body = breakout_candle.open - breakout_candle.close;
   double range = breakout_candle.high - breakout_candle.low;

   if(is_strong_bearish && breakout_candle.close < consolidation_low && body > range * 0.4)
     {
      sl_price = consolidation_high;
      tp_price = breakout_candle.low;
      return true;
     }
   return false;
  }
