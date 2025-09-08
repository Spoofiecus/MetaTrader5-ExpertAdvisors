// MQL5 Expert Advisor for the Big Candle Drawback Strategy
// Coded by Jules

#property copyright "User"
#property link      "https://github.com/Jules"
#property version   "1.00"
#property description "Implements the Big Candle Drawback Strategy."

//+------------------------------------------------------------------+
//| Include Trade Library                                            |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| EA Inputs                                                        |
//+------------------------------------------------------------------+
//--- Big Candle Definition
sinput group           "Big Candle Definition"
input double           inp_big_candle_pips      = 15.0;  // Minimum Pips for a Big Candle
input int              inp_candle_avg_lookback  = 20;    // Lookback for Average Candle Size
input double           inp_candle_size_multi    = 1.5;   // Candle Size Multiplier vs Average
input bool             inp_use_atr_spike        = true;  // Use ATR Spike Confirmation
input bool             inp_use_volume_spike     = true;  // Use Volume Spike Confirmation

//--- Momentum Confirmation
sinput group           "Indicator Settings"
input int              inp_atr_period           = 14;    // ATR Period
input int              inp_rsi_period           = 7;     // RSI Period
input double           inp_rsi_ob               = 70.0;  // RSI Overbought Level
input double           inp_rsi_os               = 30.0;  // RSI Oversold Level
input int              inp_stoch_k_period       = 5;     // Stochastic %K Period
input int              inp_stoch_d_period       = 3;     // Stochastic %D Period
input int              inp_stoch_slowing        = 3;     // Stochastic Slowing

//--- Drawback & Entry
sinput group           "Drawback & Entry"
input int              inp_ema_period           = 9;     // EMA Period
input int              inp_pullback_max_candles = 5;     // Max Candles for Pullback
input double           inp_fib_level_1          = 38.2;  // Fibonacci Retracement 1 (%)
input double           inp_fib_level_2          = 50.0;  // Fibonacci Retracement 2 (%)
input double           inp_fib_level_3          = 61.8;  // Fibonacci Retracement 3 (%)

//--- Risk Management
sinput group           "Risk Management"
input double           inp_lots                 = 0.01;  // Trade Lot Size
input ulong            inp_magic_number         = 12345; // EA Magic Number
input double           inp_sl_pips              = 5.0;   // Stop Loss Buffer (Pips)
input double           inp_tp_rr                = 2.0;   // Take Profit Risk/Reward Ratio
input bool             inp_use_rr_tp            = true;  // Use Risk/Reward for TP (if false, targets candle high/low)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
//--- Trade object
CTrade g_trade;

//--- Indicator handles
int g_atr_handle;
int g_rsi_handle;
int g_stoch_handle;
int g_ema_handle;

//--- Strategy state variables
double g_big_candle_high    = 0;
double g_big_candle_low     = 0;
long   g_big_candle_time    = 0; // Using time of bar[1] to identify the candle
bool   g_is_bullish_setup   = false;
bool   g_is_bearish_setup   = false;

//+------------------------------------------------------------------+
//| Forward Declarations for Helper Functions                        |
//+------------------------------------------------------------------+
void ResetSetup();
void CheckForBigCandle();
void CheckForEntry();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize trade object
   g_trade.SetExpertMagicNumber(inp_magic_number);
   g_trade.SetMarginMode(); // Use account's margin mode
   g_trade.SetTypeFillingBySymbol(_Symbol);

//--- Get indicator handles
   g_atr_handle=iATR(_Symbol,_Period,inp_atr_period);
   if(g_atr_handle==INVALID_HANDLE)
     {
      Print("Error getting ATR indicator handle. Error code: ",GetLastError());
      return(INIT_FAILED);
     }

   g_rsi_handle=iRSI(_Symbol,_Period,inp_rsi_period,PRICE_CLOSE);
   if(g_rsi_handle==INVALID_HANDLE)
     {
      Print("Error getting RSI indicator handle. Error code: ",GetLastError());
      return(INIT_FAILED);
     }

   g_stoch_handle=iStochastic(_Symbol,_Period,inp_stoch_k_period,inp_stoch_d_period,inp_stoch_slowing,MODE_SMA,STO_LOWHIGH);
   if(g_stoch_handle==INVALID_HANDLE)
     {
      Print("Error getting Stochastic indicator handle. Error code: ",GetLastError());
      return(INIT_FAILED);
     }

   g_ema_handle=iMA(_Symbol,_Period,inp_ema_period,0,MODE_EMA,PRICE_CLOSE);
   if(g_ema_handle==INVALID_HANDLE)
     {
      Print("Error getting EMA indicator handle. Error code: ",GetLastError());
      return(INIT_FAILED);
     }

//--- Initialization successful
   Print("Big Candle Drawback EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator handles
   IndicatorRelease(g_atr_handle);
   IndicatorRelease(g_rsi_handle);
   IndicatorRelease(g_stoch_handle);
   IndicatorRelease(g_ema_handle);

   Print("Big Candle Drawback EA deinitialized.");
  }

//+------------------------------------------------------------------+
//| Resets the trade setup state                                     |
//+------------------------------------------------------------------+
void ResetSetup()
  {
   g_is_bullish_setup=false;
   g_is_bearish_setup=false;
   g_big_candle_high=0;
   g_big_candle_low=0;
   g_big_candle_time=0;
   Comment(""); // Clear chart comment
   // Print("Setup Reset.");
  }

//+------------------------------------------------------------------+
//| Checks for the big candle pattern on the last closed bar         |
//+------------------------------------------------------------------+
void CheckForBigCandle()
  {
//--- We only check for a big candle if there is no active trade setup
   if(g_is_bullish_setup || g_is_bearish_setup)
      return;

//--- Get historical data for the last 21 bars (for averages)
   MqlRates rates[];
   if(CopyRates(_Symbol,_Period,0,inp_candle_avg_lookback+1,rates)<inp_candle_avg_lookback+1)
      return;

//--- We analyze bar at index 1 (the last fully formed candle)
   double candle_high = rates[1].high;
   double candle_low  = rates[1].low;
   double candle_open = rates[1].open;
   double candle_close= rates[1].close;
   long   candle_volume = rates[1].tick_volume;

//--- 1. Big Candle Definition: Check pip size
   double candle_size_pips = (candle_high - candle_low) / (_Point * 10.0);
   if(candle_size_pips < inp_big_candle_pips)
      return;

//--- Check against average candle size
   double total_size=0;
   for(int i=2; i<=inp_candle_avg_lookback+1; i++)
     {
      total_size += rates[i].high - rates[i].low;
     }
   double avg_candle_size = total_size / inp_candle_avg_lookback;
   if((candle_high - candle_low) < avg_candle_size * inp_candle_size_multi)
      return;

//--- Check for ATR spike
   if(inp_use_atr_spike)
     {
      double atr_buffer[2];
      if(CopyBuffer(g_atr_handle,0,1,2,atr_buffer)<2) return;
      if(atr_buffer[0] < (atr_buffer[1] * 1.2)) // ATR on bar 1 must be 20% > bar 2
         return;
     }

//--- Check for Volume spike
   if(inp_use_volume_spike)
     {
      long total_volume=0;
      for(int i=2; i<=inp_candle_avg_lookback+1; i++)
        {
         total_volume+=rates[i].tick_volume;
        }
      double avg_volume = total_volume / (double)inp_candle_avg_lookback;
      if(candle_volume < avg_volume * 1.5)
         return;
     }

//--- 2. Momentum Confirmation
   double rsi_buffer[2];
   if(CopyBuffer(g_rsi_handle,0,1,2,rsi_buffer)<2) return;

   double stoch_main[2];
   if(CopyBuffer(g_stoch_handle,0,1,2,stoch_main)<2) return;

   bool is_bullish = candle_close > candle_open;
   bool is_bearish = candle_close < candle_open;
   bool momentum_ok = false;

   if(is_bullish && rsi_buffer[0] > inp_rsi_ob && stoch_main[0] > 80)
     {
      momentum_ok=true;
     }
   if(is_bearish && rsi_buffer[0] < inp_rsi_os && stoch_main[0] < 20)
     {
      momentum_ok=true;
     }

   if(!momentum_ok)
      return;

//--- 3. We have a Big Candle! Set the state.
   if(is_bullish)
     {
      g_is_bullish_setup=true;
      Print("New Bullish Big Candle detected at ",TimeToString(rates[1].time));
      Comment("Bullish Big Candle detected. Waiting for pullback.");
     }
   else // is_bearish
     {
      g_is_bearish_setup=true;
      Print("New Bearish Big Candle detected at ",TimeToString(rates[1].time));
      Comment("Bearish Big Candle detected. Waiting for pullback.");
     }

   g_big_candle_high = candle_high;
   g_big_candle_low  = candle_low;
   g_big_candle_time = rates[1].time;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check for a new bar
   static ulong last_bar_time = 0;
   MqlRates rates[];
   if(CopyRates(_Symbol,_Period,0,1,rates)<1) return;
   ulong current_bar_time = (ulong)rates[0].time;

   if(current_bar_time == last_bar_time)
     {
      return; // Not a new bar, do nothing
     }
   last_bar_time = current_bar_time;

//--- If a trade is already open by this EA, do nothing for new signals
   if(PositionSelect(_Symbol))
     {
      if(PositionGetInteger(POSITION_MAGIC) == inp_magic_number)
        {
         // Trailing stop logic could be added here in the future
         return;
        }
     }

//--- Reset setup if the pullback window has passed
   if(g_is_bullish_setup || g_is_bearish_setup)
     {
      // iBarShift returns the number of bars between the specified time and the present (bar 0)
      int bars_since_setup = iBarShift(_Symbol, _Period, (datetime)g_big_candle_time);
      if(bars_since_setup > inp_pullback_max_candles)
        {
         Print("Pullback window expired. Resetting setup.");
         ResetSetup();
        }
     }

//--- Main logic: check for a new big candle setup or an entry
   CheckForBigCandle();
   CheckForEntry();
  }

//+------------------------------------------------------------------+
//| Checks for a trade entry based on the active setup               |
//+------------------------------------------------------------------+
void CheckForEntry()
  {
//--- Only run if there is an active setup and no open positions
   if(!g_is_bullish_setup && !g_is_bearish_setup)
      return;

//--- Get latest price data
   MqlRates rates[];
   if(CopyRates(_Symbol,_Period,0,3,rates)<3) return; // Need 3 bars for reversal pattern

//--- Calculate Fib levels
   double fib_range = g_big_candle_high - g_big_candle_low;
   double fib1 = g_is_bullish_setup ? g_big_candle_high - fib_range * (inp_fib_level_1/100.0) : g_big_candle_low + fib_range * (inp_fib_level_1/100.0);
   double fib2 = g_is_bullish_setup ? g_big_candle_high - fib_range * (inp_fib_level_2/100.0) : g_big_candle_low + fib_range * (inp_fib_level_2/100.0);
   double fib3 = g_is_bullish_setup ? g_big_candle_high - fib_range * (inp_fib_level_3/100.0) : g_big_candle_low + fib_range * (inp_fib_level_3/100.0);

//--- Check Retracement and Reversal on bar[1] (the last closed bar)
   bool retracement_ok = false;
   bool reversal_ok = false;

   //--- Bullish Entry Check
   if(g_is_bullish_setup)
     {
      // Check if the low of the last bar touched a fib level
      if(rates[1].low <= fib1 || rates[1].low <= fib2 || rates[1].low <= fib3)
         retracement_ok=true;
      // Check for a simple bullish reversal candle
      if(rates[1].close > rates[1].open && rates[2].close < rates[2].open)
         reversal_ok=true;
     }

   //--- Bearish Entry Check
   if(g_is_bearish_setup)
     {
      // Check if the high of the last bar touched a fib level
      if(rates[1].high >= fib1 || rates[1].high >= fib2 || rates[1].high >= fib3)
         retracement_ok=true;
      // Check for a simple bearish reversal candle
      if(rates[1].close < rates[1].open && rates[2].close > rates[2].open)
         reversal_ok=true;
     }

   if(!retracement_ok || !reversal_ok)
      return;

//--- Final Entry Conditions: RSI and Volume
   double rsi_buffer[2];
   if(CopyBuffer(g_rsi_handle,0,1,2,rsi_buffer)<2) return; // rsi on bar[1] is at index 0 of buffer

   bool final_conditions_ok = false;
   if(g_is_bullish_setup && rsi_buffer[0] > 40 && rates[1].tick_volume < rates[2].tick_volume)
     {
      final_conditions_ok=true;
     }
   if(g_is_bearish_setup && rsi_buffer[0] < 60 && rates[1].tick_volume < rates[2].tick_volume)
     {
      final_conditions_ok=true;
     }

   if(!final_conditions_ok)
      return;

//--- All conditions are met, EXECUTE TRADE
   double price = SymbolInfoDouble(_Symbol,g_is_bullish_setup ? SYMBOL_ASK : SYMBOL_BID);
   double sl=0, tp=0;

   if(g_is_bullish_setup)
     {
      sl = g_big_candle_low - inp_sl_pips * _Point * 10.0;
      tp = inp_use_rr_tp ? price + (price - sl) * inp_tp_rr : g_big_candle_high;
      g_trade.Buy(inp_lots,_Symbol,price,sl,tp,"BCD Buy");
     }
   else // Bearish setup
     {
      sl = g_big_candle_high + inp_sl_pips * _Point * 10.0;
      tp = inp_use_rr_tp ? price - (sl - price) * inp_tp_rr : g_big_candle_low;
      g_trade.Sell(inp_lots,_Symbol,price,sl,tp,"BCD Sell");
     }

//--- Reset state after attempting to place trade
   if(g_trade.ResultRetcode()==TRADE_RETCODE_DONE || g_trade.ResultRetcode()==TRADE_RETCODE_PLACED)
     {
      Print("Trade successfully placed. Resetting setup.");
     }
   else
     {
      Print("Trade execution failed. Error: ",g_trade.ResultRetcode(),". Message: ",g_trade.ResultComment());
     }
   ResetSetup();
  }
