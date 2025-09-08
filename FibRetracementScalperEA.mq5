// MQL5 Expert Advisor for the Fibonacci Retracement Scalping Strategy
// Coded by Jules

#property copyright "User"
#property link      "https://github.com/Jules"
#property version   "1.0"
#property description "Scalps trends by entering on Fibonacci retracements."

//+------------------------------------------------------------------+
//| Include Trade Library                                            |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| EA Inputs                                                        |
//+------------------------------------------------------------------+
//--- Trend Identification
sinput group                 "Trend Identification"
input ENUM_TIMEFRAMES        inp_trend_tf           = PERIOD_M15;  // Higher Timeframe for Trend
input int                    inp_trend_ema_period   = 200;         // Trend EMA Period

//--- Swing Detection (ZigZag)
sinput group                 "Swing Detection (ZigZag)"
input int                    inp_zigzag_depth       = 12;          // ZigZag: Depth
input int                    inp_zigzag_deviation   = 5;           // ZigZag: Deviation
input int                    inp_zigzag_backstep    = 3;           // ZigZag: Backstep

//--- Fibonacci & Entry
sinput group                 "Fibonacci & Entry Settings"
input bool                   inp_use_fib_1          = true;        // Use Fib Level 1?
input double                 inp_fib_level_1        = 38.2;        // Fib Retracement Level 1 (%)
input bool                   inp_use_fib_2          = true;        // Use Fib Level 2?
input double                 inp_fib_level_2        = 50.0;        // Fib Retracement Level 2 (%)
input bool                   inp_use_fib_3          = true;        // Use Fib Level 3?
input double                 inp_fib_level_3        = 61.8;        // Fib Retracement Level 3 (%)

//--- Risk Management
sinput group                 "Risk Management"
input double                 inp_lots               = 0.01;        // Trade Lot Size
input ulong                  inp_magic_number       = 54321;       // EA Magic Number
input double                 inp_sl_pips_buffer     = 10.0;        // SL Buffer (Pips) Beyond Swing
input double                 inp_tp_rr              = 1.5;         // Take Profit Risk/Reward Ratio
input string                 inp_comment            = "FibScalp";  // Trade Comment

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade          g_trade;
int             g_trend_ema_handle;
int             g_zigzag_handle;

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
// void CheckForEntry(); // To be added later
void CheckAndManageTrade();

//--- State Management
bool   g_setup_active = false;
double g_fib_1, g_fib_2, g_fib_3;
double g_swing_for_sl; // The swing point (low/high) to place the SL beyond

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize trade object
   g_trade.SetExpertMagicNumber(inp_magic_number);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

//--- Get Trend EMA handle on the higher timeframe
   g_trend_ema_handle=iMA(_Symbol,inp_trend_tf,inp_trend_ema_period,0,MODE_EMA,PRICE_CLOSE);
   if(g_trend_ema_handle==INVALID_HANDLE)
     {
      Print("Error getting Trend EMA indicator handle. Error: ",GetLastError());
      return(INIT_FAILED);
     }

//--- Get ZigZag indicator handle
   g_zigzag_handle=iCustom(_Symbol,_Period,"Examples\\ZigZag",
                           inp_zigzag_depth,inp_zigzag_deviation,inp_zigzag_backstep);
   if(g_zigzag_handle==INVALID_HANDLE)
     {
      Print("Error getting ZigZag indicator handle. Error: ",GetLastError());
      return(INIT_FAILED);
     }

   Print("Fibonacci Retracement Scalper EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator handles
   IndicatorRelease(g_trend_ema_handle);
   IndicatorRelease(g_zigzag_handle);
   Print("Fibonacci Retracement Scalper EA deinitialized.");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Standard new bar check
   static datetime last_bar_time = 0;
   MqlRates rates[];
   if(CopyRates(_Symbol,_Period,0,1,rates)<1) return;
   if(rates[0].time == last_bar_time) return;
   last_bar_time=rates[0].time;

//--- Do not run if a trade is already open
   if(PositionSelect(_Symbol))
     {
      if(PositionGetInteger(POSITION_MAGIC) == inp_magic_number)
         return;
     }

   //--- Run the main logic
   CheckAndManageTrade();
  }

//+------------------------------------------------------------------+
//| Main logic function                                              |
//+------------------------------------------------------------------+
void CheckAndManageTrade()
  {
//--- 1. Determine Trend
   MqlRates current_rates[3]; // Need 3 for reversal pattern
   if(CopyRates(_Symbol,_Period,0,3,current_rates)<3) return;

   double htf_ema_buffer[1];
   if(CopyBuffer(g_trend_ema_handle,0,0,1,htf_ema_buffer)<1) return;
   double htf_ema_value = htf_ema_buffer[0];
   bool is_uptrend = (current_rates[0].close > htf_ema_value);
   bool is_downtrend = (current_rates[0].close < htf_ema_value);

   if(!is_uptrend && !is_downtrend)
     {
      g_setup_active=false; // No trend, no setup
      return;
     }

//--- 2. Find Swings
   double zigzag_high_buffer[200], zigzag_low_buffer[200];
   if(CopyBuffer(g_zigzag_handle,1,0,200,zigzag_high_buffer)<200 || CopyBuffer(g_zigzag_handle,2,0,200,zigzag_low_buffer)<200) return;

   double last_high_val=0, last_low_val=0;
   int last_high_idx=0, last_low_idx=0;
   for(int i=1; i<200; i++) { if(zigzag_high_buffer[i]>0) { last_high_val=zigzag_high_buffer[i]; last_high_idx=i; break; } }
   for(int i=1; i<200; i++) { if(zigzag_low_buffer[i]>0)  { last_low_val=zigzag_low_buffer[i]; last_low_idx=i; break; } }
   if(last_high_val==0 || last_low_val==0) return;

//--- 3. Determine latest swing and check if it's new
   double swing_start, swing_end;
   bool swing_is_up;
   if(last_high_idx > last_low_idx) { swing_start=last_high_val; swing_end=last_low_val; swing_is_up=false; }
   else { swing_start=last_low_val; swing_end=last_high_val; swing_is_up=true; }

   static double last_swing_end_val = 0;
   if(swing_end != last_swing_end_val)
     {
      last_swing_end_val = swing_end;
      g_setup_active = false; // New swing invalidates old setup

      // 4. Validate swing and calculate Fibs if it's a new, valid setup
      if((is_uptrend && swing_is_up) || (is_downtrend && !swing_is_up))
        {
         double swing_range = MathAbs(swing_end - swing_start);
         g_swing_for_sl = swing_start;
         if(is_uptrend)
           {
            g_fib_1 = swing_end - swing_range * (inp_fib_level_1/100.0);
            g_fib_2 = swing_end - swing_range * (inp_fib_level_2/100.0);
            g_fib_3 = swing_end - swing_range * (inp_fib_level_3/100.0);
           }
         else // downtrend
           {
            g_fib_1 = swing_end + swing_range * (inp_fib_level_1/100.0);
            g_fib_2 = swing_end + swing_range * (inp_fib_level_2/100.0);
            g_fib_3 = swing_end + swing_range * (inp_fib_level_3/100.0);
           }
         g_setup_active = true;
         Comment("New Fib setup active. Waiting for pullback.");
        }
     }

//--- 5. Entry Logic
   if(!g_setup_active)
     {
      Comment(is_uptrend ? "Uptrend" : is_downtrend ? "Downtrend" : "No Trend");
      return;
     }

   bool touch_ok = false, reversal_ok = false;
   if(is_uptrend)
     {
      if((inp_use_fib_1 && current_rates[1].low <= g_fib_1) || (inp_use_fib_2 && current_rates[1].low <= g_fib_2) || (inp_use_fib_3 && current_rates[1].low <= g_fib_3)) touch_ok=true;

      // Bullish Engulfing Pattern Check
      bool is_bullish_engulfing = current_rates[1].close > current_rates[1].open &&   // Current is bullish
                                  current_rates[2].close < current_rates[2].open &&   // Previous was bearish
                                  current_rates[1].close > current_rates[2].open &&   // Current close is higher than previous open
                                  current_rates[1].open < current_rates[2].close;     // Current open is lower than previous close
      if(is_bullish_engulfing) reversal_ok=true;
     }
   else // downtrend
     {
      if((inp_use_fib_1 && current_rates[1].high >= g_fib_1) || (inp_use_fib_2 && current_rates[1].high >= g_fib_2) || (inp_use_fib_3 && current_rates[1].high >= g_fib_3)) touch_ok=true;

      // Bearish Engulfing Pattern Check
      bool is_bearish_engulfing = current_rates[1].close < current_rates[1].open &&   // Current is bearish
                                  current_rates[2].close > current_rates[2].open &&   // Previous was bullish
                                  current_rates[1].close < current_rates[2].open &&   // Current close is lower than previous open
                                  current_rates[1].open > current_rates[2].close;     // Current open is higher than previous close
      if(is_bearish_engulfing) reversal_ok=true;
     }

   if(touch_ok && reversal_ok)
     {
      double sl, tp, price;
      //--- Adjust pip value for 3/5 digit brokers
      double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * (SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 ? 10 : 1);

      if(is_uptrend)
        {
         price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         sl = g_swing_for_sl - inp_sl_pips_buffer * pip_value;
         tp = price + (price - sl) * inp_tp_rr;
         g_trade.Buy(inp_lots,_Symbol,price,sl,tp,inp_comment);
        }
      else // downtrend
        {
         price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
         sl = g_swing_for_sl + inp_sl_pips_buffer * pip_value;
         tp = price - (sl - price) * inp_tp_rr;
         g_trade.Sell(inp_lots,_Symbol,price,sl,tp,inp_comment);
        }
      g_setup_active = false; // Reset after trade
      Comment("Trade Executed!");
     }
  }
