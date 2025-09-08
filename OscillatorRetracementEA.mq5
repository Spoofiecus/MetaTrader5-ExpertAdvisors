// MQL5 Expert Advisor for the RSI/Stochastic Oscillator Retracement Strategy
// Coded by Jules

#property copyright "User"
#property link      "https://github.com/Jules"
#property version   "1.0"
#property description "Trades oscillator pullbacks in a strong trend."

//+------------------------------------------------------------------+
//| Include Trade Library                                            |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_OSCILLATOR_TYPE
  {
   OSC_RSI,         // Use RSI
   OSC_STOCHASTIC   // Use Stochastic
  };

//+------------------------------------------------------------------+
//| EA Inputs                                                        |
//+------------------------------------------------------------------+
//--- Trend Filter
sinput group                 "Trend Filter Settings"
input ENUM_TIMEFRAMES        inp_trend_tf           = PERIOD_M15;  // Higher Timeframe for Trend EMA
input int                    inp_trend_ema_period   = 200;         // Trend EMA Period

//--- Oscillator Choice
sinput group                 "Oscillator Settings"
input ENUM_OSCILLATOR_TYPE   inp_osc_type           = OSC_RSI;     // Oscillator to Use for Signals

//--- RSI Settings
sinput group                 "RSI Settings"
input int                    inp_rsi_period         = 14;          // RSI Period
input double                 inp_rsi_ob_level       = 70.0;        // RSI Overbought Level
input double                 inp_rsi_os_level       = 30.0;        // RSI Oversold Level

//--- Stochastic Settings
sinput group                 "Stochastic Settings"
input int                    inp_stoch_k_period     = 5;           // Stochastic %K
input int                    inp_stoch_d_period     = 3;           // Stochastic %D
input int                    inp_stoch_slowing      = 3;           // Stochastic Slowing
input double                 inp_stoch_ob_level     = 80.0;        // Stochastic Overbought Level
input double                 inp_stoch_os_level     = 20.0;        // Stochastic Oversold Level

//--- Confirmation & Risk
sinput group                 "Confirmation & Risk Management"
input bool                   inp_use_volume_confirm = true;         // Use Volume Confirmation?
input double                 inp_lots               = 0.01;        // Trade Lot Size
input double                 inp_tp_pips            = 15.0;        // Take Profit (Pips)
input double                 inp_sl_buffer_pips     = 2.0;         // SL Buffer (Pips) from Candle High/Low
input ulong                  inp_magic_number       = 76543;       // EA Magic Number
input string                 inp_comment            = "OscRetrace"; // Trade Comment

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade          g_trade;
int             g_trend_ema_handle;
int             g_rsi_handle;
int             g_stoch_handle;

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

//--- Get RSI handle
   g_rsi_handle=iRSI(_Symbol,_Period,inp_rsi_period,PRICE_CLOSE);
   if(g_rsi_handle==INVALID_HANDLE)
     {
      Print("Error getting RSI indicator handle: ",GetLastError());
      return(INIT_FAILED);
     }

//--- Get Stochastic handle
   g_stoch_handle=iStochastic(_Symbol,_Period,inp_stoch_k_period,inp_stoch_d_period,inp_stoch_slowing,MODE_SMA,STO_LOWHIGH);
   if(g_stoch_handle==INVALID_HANDLE)
     {
      Print("Error getting Stochastic indicator handle: ",GetLastError());
      return(INIT_FAILED);
     }

   Print("Oscillator Retracement EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(g_trend_ema_handle);
   IndicatorRelease(g_rsi_handle);
   IndicatorRelease(g_stoch_handle);
   Print("Oscillator Retracement EA deinitialized.");
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
//--- Get latest price data
   MqlRates rates[3];
   if(CopyRates(_Symbol,_Period,0,3,rates)<3) return;

//--- 1. Determine Trend
   double htf_ema_buffer[1];
   if(CopyBuffer(g_trend_ema_handle,0,0,1,htf_ema_buffer)<1) return;
   bool is_uptrend = (rates[0].close > htf_ema_buffer[0]);
   bool is_downtrend = (rates[0].close < htf_ema_buffer[0]);
   if(!is_uptrend && !is_downtrend) return;

//--- 2. Get Oscillator Data based on user choice
   double osc_buffer[3];
   double ob_level, os_level;

   if(inp_osc_type==OSC_RSI)
     {
      if(CopyBuffer(g_rsi_handle,0,0,3,osc_buffer)<3) return;
      ob_level=inp_rsi_ob_level;
      os_level=inp_rsi_os_level;
     }
   else // OSC_STOCHASTIC
     {
      if(CopyBuffer(g_stoch_handle,0,0,3,osc_buffer)<3) return; // 0 is main line
      ob_level=inp_stoch_ob_level;
      os_level=inp_stoch_os_level;
     }

//--- 3. Entry Pattern Detection (The "Rebound")
   bool buy_setup = false;
   if(is_uptrend)
     {
      // Dip below oversold on bar[2], then cross back above on bar[1]
      if(osc_buffer[2] < os_level && osc_buffer[1] > os_level)
        {
         buy_setup=true;
        }
     }

   bool sell_setup = false;
   if(is_downtrend)
     {
      // Spike above overbought on bar[2], then cross back below on bar[1]
      if(osc_buffer[2] > ob_level && osc_buffer[1] < ob_level)
        {
         sell_setup=true;
        }
     }

   if(!buy_setup && !sell_setup) return;

//--- 4. Volume Confirmation
   if(inp_use_volume_confirm)
     {
      if(rates[1].tick_volume <= rates[2].tick_volume)
        {
         // Volume did not confirm, invalidate setup
         return;
        }
     }

//--- If a setup is found, execute the trade
   if(buy_setup)
     {
      ExecuteBuy(rates[1]);
     }
   else if(sell_setup)
     {
      ExecuteSell(rates[1]);
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
