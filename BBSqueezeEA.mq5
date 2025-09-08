// MQL5 Expert Advisor for the Bollinger Bands Retracement Squeeze Strategy
// Coded by Jules (Version 1.2 - Corrected breakout logic)

#property copyright "User"
#property link      "https://github.com/Jules"
#property version   "1.2"
#property description "Trades breakouts after a Bollinger Bands squeeze."

//+------------------------------------------------------------------+
//| Include Trade Library                                            |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| EA Inputs                                                        |
//+------------------------------------------------------------------+
//--- Trend Filter
sinput group                 "Trend Filter Settings"
input ENUM_TIMEFRAMES        inp_trend_tf           = PERIOD_M15;  // Higher Timeframe for Trend EMA
input int                    inp_trend_ema_period   = 200;         // Trend EMA Period

//--- Bollinger Bands Settings
sinput group                 "Bollinger Bands Settings"
input int                    inp_bb_period          = 20;          // BB Period
input double                 inp_bb_deviation       = 2.0;         // BB Deviation

//--- Squeeze Detection
sinput group                 "Squeeze Detection"
input int                    inp_squeeze_lookback   = 100;         // Lookback period for Squeeze

//--- Risk Management
sinput group                 "Risk Management"
input double                 inp_lots               = 0.01;        // Trade Lot Size
input double                 inp_tp_pips            = 20.0;        // Take Profit (Pips)
input double                 inp_sl_buffer_pips     = 2.0;         // SL Buffer (Pips) from Candle High/Low
input ulong                  inp_magic_number       = 87654;       // EA Magic Number
input string                 inp_comment            = "BBSqueeze"; // Trade Comment

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade          g_trade;
int             g_trend_ema_handle;
int             g_bb_handle;

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
void CheckAndManageTrade();
void ExecuteBuy(const MqlRates &entry_candle);
void ExecuteSell(const MqlRates &entry_candle);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(inp_magic_number);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

//--- Get Trend EMA handle
   g_trend_ema_handle=iMA(_Symbol,inp_trend_tf,inp_trend_ema_period,0,MODE_EMA,PRICE_CLOSE);
   if(g_trend_ema_handle==INVALID_HANDLE)
     {
      Print("Error getting Trend EMA indicator handle: ",GetLastError());
      return(INIT_FAILED);
     }

//--- Get Bollinger Bands handle
   g_bb_handle=iBands(_Symbol,_Period,inp_bb_period,0,inp_bb_deviation,PRICE_CLOSE);
   if(g_bb_handle==INVALID_HANDLE)
     {
      Print("Error getting Bollinger Bands indicator handle: ",GetLastError());
      return(INIT_FAILED);
     }

   Print("BB Squeeze EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(g_trend_ema_handle);
   IndicatorRelease(g_bb_handle);
   Print("BB Squeeze EA deinitialized.");
  }

//--- State Management
bool g_squeeze_active = false; // Global flag for active squeeze

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
//--- 1. Get Data
   int lookback = inp_squeeze_lookback + 2;
   MqlRates rates[];
   if(CopyRates(_Symbol,_Period,0,lookback,rates)<lookback) return;

   double upper_band[lookback], lower_band[lookback];
   if(CopyBuffer(g_bb_handle,1,0,lookback,upper_band)<lookback ||
      CopyBuffer(g_bb_handle,2,0,lookback,lower_band)<lookback) return;

//--- 2. Determine Trend
   MqlRates htf_rates[];
   if(CopyRates(_Symbol, inp_trend_tf, 0, 1, htf_rates) < 1) return;

   double htf_ema_buffer[1];
   if(CopyBuffer(g_trend_ema_handle,0,0,1,htf_ema_buffer)<1) return;
   bool is_uptrend = (rates[0].close > htf_ema_buffer[0]);
   bool is_downtrend = (rates[0].close < htf_ema_buffer[0]);
   if(!is_uptrend && !is_downtrend) return;

//--- 3. Squeeze Detection (on bar[1], the bar before the breakout)
   double squeeze_check_width = upper_band[1] - lower_band[1];
   double min_width = squeeze_check_width;
   for(int i=2; i<inp_squeeze_lookback+1; i++) // Loop through historical widths
     {
      double historic_width = upper_band[i] - lower_band[i];
      if(historic_width < min_width)
        {
         min_width = historic_width;
        }
     }

   if(squeeze_check_width <= min_width)
     {
      g_squeeze_active = true;
     }

//--- 4. Breakout Detection (on bar[0], the most recent closed bar)
   if(g_squeeze_active)
     {
      bool breakout_buy = is_uptrend && rates[0].close > upper_band[0];
      bool breakout_sell = is_downtrend && rates[0].close < lower_band[0];

      if(breakout_buy)
        {
         ExecuteBuy(rates[0]);
         g_squeeze_active=false; // Reset after breakout
        }
      else if(breakout_sell)
        {
         ExecuteSell(rates[0]);
         g_squeeze_active=false; // Reset after breakout
        }

      // If the bands expand without a breakout, reset the squeeze state
      double current_width = upper_band[0] - lower_band[0];
      if (current_width > squeeze_check_width * 1.5)
        {
         g_squeeze_active = false;
        }
     }
  }

//+------------------------------------------------------------------+
//| Executes a Buy Trade                                             |
//+------------------------------------------------------------------+
void ExecuteBuy(const MqlRates &entry_candle)
  {
   double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * (SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 ? 10 : 1);
   double price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl = entry_candle.low - inp_sl_buffer_pips * pip_value;
   double tp = price + inp_tp_pips * pip_value;

   if(!g_trade.Buy(inp_lots,_Symbol,price,sl,tp,inp_comment))
     {
      Print("Buy order execution failed. Error: ",g_trade.ResultRetcode(),". Message: ",g_trade.ResultComment());
     }
   else
     {
      Print("Buy order placed successfully at ", price);
     }
  }

//+------------------------------------------------------------------+
//| Executes a Sell Trade                                            |
//+------------------------------------------------------------------+
void ExecuteSell(const MqlRates &entry_candle)
  {
   double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * (SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5 ? 10 : 1);
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl = entry_candle.high + inp_sl_buffer_pips * pip_value;
   double tp = price - inp_tp_pips * pip_value;

   if(!g_trade.Sell(inp_lots,_Symbol,price,sl,tp,inp_comment))
     {
      Print("Sell order execution failed. Error: ",g_trade.ResultRetcode(),". Message: ",g_trade.ResultComment());
     }
   else
     {
      Print("Sell order placed successfully at ", price);
     }
  }
