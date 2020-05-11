//+------------------------------------------------------------------+
//|                                                     3BarPlay.mq5 |
//|                                                               JG |
//|                                                             None |
//+------------------------------------------------------------------+
//--- input parameters
input int stopLoss = 64;            //Stop Loss
input int takeProfit = 113;         //Take Profit
input double lotSize = 0.01;        //Lot Size
input int barIntervalThreshold = 6; // Bar Trade interval

//---Optimisation input parameters
input double takePositionThreshold = 2; //Enter after price = final bar close + X points
input double closeDistance = 1;         //Each bar must Close X points above previous
input double openDistance = 1;          //Each bar must Open X points above previous
input double minPoints = 2;             //Each bar must be > X number of points
input double barWickSize = 1;           //Higher Number = Smaller Wicks
input bool waitForConfBar = true;       //Wait for Conf bar

input int rsiLongUpperLimit=0;          //Long RSI Upper limit CA - Upper 100
input int rsiLongLowerLimit=0;          //Long RSI Lower limit CA - Lower 0
input int rsiShortUpperLimit=0;         //Short RSI Upper limit CA - Upper 100
input int rsiShortLowerLimit=0;         //Short RSI Lower limit CA - Lower 0
 
input int upperStochLimit=0;          //Stoch Upper limit CA - Upper 0
input int lowerStochLimit=0;          //Stoch Lower limit CA - Lower 100

input bool makeShortTrades = false;     //Make Short trades
input bool makeLongTrades = false;      //Make Long trades
input bool weirdRevertLong = false;     //Short when Signals say Long
input bool weirdRevertShort = false;    //Long when Signals say Short

//--- Other parameters
int movingAveragePeriod = 50;
int expertAdvisorMagicNumber = 12345;

int movingAverageHandler; // handle for our Moving Average indicator
double movingAverages[];  // Dynamic array to hold the values of Moving Average for each bars

double volume[];
double rsi[];

double stoch_K[];
double stoch_D[];

string currentTime = "";
bool isNewBar = false;

bool positionTakenThisBar = false;
bool tradeBarCounterActive = 0;
int barsSinceLastTrade = 0;

int OnInit()
{
  //--- Get the handle for Moving Average indicator
  movingAverageHandler = iMA(_Symbol, _Period, movingAveragePeriod, 0, MODE_EMA, PRICE_CLOSE);

  //--- What if handle returns Invalid Handle
  if (movingAverageHandler < 0)
  {
    Alert("Error Creating Handles for indicators - error: ", GetLastError(), "!!");
  }
  
  Alert("STOP LOSS MIN: " + SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL));
  
  return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
  IndicatorRelease(movingAverageHandler);
}

void OnTick()
{
  static datetime oldTime;
  datetime newTime[1];

  // copying the last bar time to the element newTime[0]
  int copied = CopyTime(_Symbol, _Period, 0, 1, newTime);
  if (copied > 0) // ok, the data has been copied successfully
  {
    if (oldTime != newTime[0]) // if old time isn't equal to new bar time
    {
      isNewBar = true; // if it isn't a first call, the new bar has appeared
      if (MQL5InfoInteger(MQL5_DEBUGGING))
        Print("We have new bar here ", newTime[0], " old time was ", oldTime);
      oldTime = newTime[0]; // saving bar time
      currentTime = TimeToString(newTime[0], TIME_DATE | TIME_MINUTES);
    }
  }
  else
  {
    Alert("Error in copying historical times data, error =", GetLastError());
    ResetLastError();
    return;
  }

  if (isNewBar == true)
  {
    if (barsSinceLastTrade > barIntervalThreshold)
    {
      tradeBarCounterActive = false;
      barsSinceLastTrade = 0;
    }

    if (tradeBarCounterActive == true)
    {
      barsSinceLastTrade = barsSinceLastTrade + 1;
    }

    positionTakenThisBar = false;
  }

  MqlTick latestPriceDetails;   // To be used for getting recent/latest price quotes
  MqlTradeRequest tradeRequest; // To be used for sending our trade requests
  MqlTradeResult tradeResult;   // To be used to get our trade results
  MqlRates barDetails[];        // To be used to store the prices, volumes and spread of each bar
  ZeroMemory(tradeRequest);     // Initialization of tradeRequest struct

  // the bar details arrays
  ArraySetAsSeries(barDetails, true);
  // the MA-8 values arrays
  ArraySetAsSeries(movingAverages, true);
  // the volume array
  ArraySetAsSeries(volume, true);
  // the volume array
  ArraySetAsSeries(rsi, true);
  // the stoch K array
  ArraySetAsSeries(stoch_K, true);
  // the stoch D array
  ArraySetAsSeries(stoch_D, true);

  //--- Get the last price quote using the MQL5 MqlTick Structure
  if (!SymbolInfoTick(_Symbol, latestPriceDetails))
  {
    Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
    return;
  }

  //--- Get the details of the latest 6 bars and MA
  if (CopyRates(_Symbol, _Period, 0, 6, barDetails) < 0)
  {
    Alert("Error copying rates/history data - error:", GetLastError(), "!!");
    return;
  }
  if (CopyBuffer(movingAverageHandler, 0, 0, 6, movingAverages) < 0)
  {
    Alert("Error copying Moving Average indicator buffer - error:", GetLastError());
    return;
  }

  //--- Get the details of the latest 6 volumes
  CopyBuffer(iVolumes(_Symbol, _Period, VOLUME_TICK), 0, 0, 6, volume);

  //--- Get the details of the latest 6 volumes
  CopyBuffer(iRSI(_Symbol, _Period, 14, PRICE_CLOSE), 0, 0, 6, rsi);
  
  //--- Get the details of the latest 6 stochs
  int stochDefinition = iStochastic(_Symbol, _Period, 5, 6, 3, MODE_SMA, STO_LOWHIGH);
  CopyBuffer(stochDefinition, 0, 0, 6,stoch_K);
  CopyBuffer(stochDefinition, 1, 0, 6, stoch_D);

  //--- We have no errors, so continue to trading

  Comment("Stoch K: " + stoch_K[0] + 
          "\nStoch D: " + stoch_D[0]);          

  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  int spread = (int)MathRound((ask - bid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT));

  if (makeLongTrades == true && checkRsiLong(rsi, rsiLongLowerLimit, rsiLongUpperLimit) && checkStochLong(stoch_K, stoch_D, lowerStochLimit, upperStochLimit) && tradeBarCounterActive == false && positionTakenThisBar == false && CheckFor3WhiteSoldiers(barDetails, ask))
  {
    if (weirdRevertLong == true)
    {
      tradeResult = MakeShortTrade(tradeRequest, tradeResult, ask);
    }
    else
    {
      tradeResult = MakeLongTrade(tradeRequest, tradeResult, bid);
    }

    if (tradeResult.retcode == 10009 || tradeResult.retcode == 10008) //Request is completed or order placed
    {
      positionTakenThisBar = true;
      tradeBarCounterActive = true;
      Alert("A Buy order at bid price: ", bid, " has been successfully placed with Ticket#:", tradeResult.order, "!!");
      return;
    }
    else
    {
      if (weirdRevertLong == true)
      {
        Alert("The Buy (SELL) order request (price: " + bid + ") could not be completed -error:", GetLastError());
      }
      else
      {
        Alert("The Buy order request (price: " + ask + ") could not be completed -error:", GetLastError());
      }

      ResetLastError();
      return;
    }
  }

  if (makeShortTrades == true && checkRsiShort(rsi, rsiShortLowerLimit, rsiShortUpperLimit)  && checkStochShort(stoch_K, stoch_D, lowerStochLimit, upperStochLimit) && tradeBarCounterActive == false && positionTakenThisBar == false && CheckFor3BlackCrows(barDetails, bid))
  {
    if (weirdRevertShort == true)
    {
      tradeResult = MakeLongTrade(tradeRequest, tradeResult, bid);
    }
    else
    {
      tradeResult = MakeShortTrade(tradeRequest, tradeResult, ask);
    }

    if (tradeResult.retcode == 10009 || tradeResult.retcode == 10008) //Request is completed or order placed
    {
      positionTakenThisBar = true;
      tradeBarCounterActive = true;
      Alert("A Sell order at bid price: ", bid, " has been successfully placed with Ticket#:", tradeResult.order, "!!");
    }
    else
    {
      if (weirdRevertShort == true)
      {
        Alert("The Sell (BUY) order request (price: " + ask + ") could not be completed -error:", GetLastError());
      }
      else
      {
        Alert("The Sell order request (price: " + bid + ") could not be completed -error:", GetLastError());
      }

      ResetLastError();
      return;
    }
  }

  isNewBar = false;
}

//Stoch check value is above the Upper limit or below the lower Limit
//Catch all - Lower 100, Upper 0
bool checkStochLong(double &stoch_K[], double &stoch_D[], double lowerStochLimit, double upperStochLimit)
{
  if (weirdRevertLong == true)
  {
    return stoch_K[0] > upperStochLimit;
  }
  else
  {
    return stoch_K[0] < lowerStochLimit;
  }
}
bool checkStochShort(double &stoch_K[], double &stoch_D[], double lowerStochLimit, double upperStochLimit)
{
  if (weirdRevertShort == true)
  {
    return stoch_K[0] < lowerStochLimit;
  }
  else
  {
    return stoch_K[0] > upperStochLimit;
  }  
}

//RSI check value is below the Upper Limit and above the Lower limit
//Catch all - Upper 100, Lower 0
bool checkRsiLong(double &rsi[], double rsiLongLowerLimit, double rsiLongUpperLimit)
{
  if (weirdRevertLong == true)
  {
    return (rsi[0] > rsiShortLowerLimit) && (rsi[0] < rsiShortUpperLimit);
  }
  else
  {
    return (rsi[0] > rsiLongLowerLimit) && (rsi[0] < rsiLongUpperLimit);
  }  
}
bool checkRsiShort(double &rsi[], double rsiShortLowerLimit, double rsiShortUpperLimit)
{
  if (weirdRevertShort == true)
  {
    return (rsi[0] > rsiLongLowerLimit) && (rsi[0] < rsiLongUpperLimit);
  }
  else
  {  
    return (rsi[0] > rsiShortLowerLimit) && (rsi[0] < rsiShortUpperLimit);
  }
  
}

bool CheckFor3WhiteSoldiers(MqlRates &barDetails[], double ask)
{
  double firstLargeGreenBarDistance = barDetails[4].close - barDetails[4].open;
  double secondLargeGreenBarDistance = barDetails[3].close - barDetails[3].open;
  double thirdLargeGreenBarDistance = barDetails[2].close - barDetails[2].open;
  double barBeforeFirstLargeGreenBarDistance = barDetails[5].close - barDetails[5].open;
  if (barBeforeFirstLargeGreenBarDistance < 0)
  {
    barBeforeFirstLargeGreenBarDistance = barDetails[5].open - barDetails[5].close;
  }

  //For easier debugging of which statement is incorrect
  if (currentTime == "2020.05.14 05:09")
  {
    Alert("Debugging Time");
  }

  //Check bars are correct type
  if (firstLargeGreenBarDistance <= 0 || secondLargeGreenBarDistance <= 0 || thirdLargeGreenBarDistance <= 0)
  {
    return false;
  }

  //third green bar close must be X above second green close, second green close must be X above first green close
  //AND third green bar open must be X above second green open, second green open must be X above first green open
  if (!(barDetails[2].close > (barDetails[3].close + (closeDistance * _Point))) || !(barDetails[3].close > (barDetails[4].close + (closeDistance * _Point))) ||
      !(barDetails[2].open > (barDetails[3].open + (openDistance * _Point))) || !(barDetails[3].close > (barDetails[4].close + (openDistance * _Point))))
  {
    return false;
  }

  //Bars must be X number of points
  if ((firstLargeGreenBarDistance < (minPoints * _Point)) || (secondLargeGreenBarDistance < (minPoints * _Point)) || (thirdLargeGreenBarDistance < (minPoints * _Point)))
  {
    return false;
  }

  //Wicks must be < than Xth of Bar
  if (barWickSize > 0)
  {
    if (!((barDetails[4].high - barDetails[4].close) < (firstLargeGreenBarDistance / barWickSize)) ||
        !((barDetails[4].open - barDetails[4].low) < (firstLargeGreenBarDistance / barWickSize)) ||
        !((barDetails[3].high - barDetails[3].close) < (secondLargeGreenBarDistance / barWickSize)) ||
        !((barDetails[3].open - barDetails[3].low) < (secondLargeGreenBarDistance / barWickSize)) ||
        !((barDetails[2].high - barDetails[2].close) < (thirdLargeGreenBarDistance / barWickSize)) ||
        !((barDetails[2].open - barDetails[2].low) < (thirdLargeGreenBarDistance / barWickSize)))
    {
      return false;
    }
  }

  //Conf bar must be Green bar
  if (waitForConfBar == true && (barDetails[1].close - barDetails[1].open) < 0)
  {
    return false;
  }

  //Take position after price has reached Final Green candles close + X points
  if (takePositionThreshold > 0 && !(ask <= (barDetails[2].high + (takePositionThreshold * _Point))))
  {
    return false;
  }

  return true;
}

bool CheckFor3BlackCrows(MqlRates &barDetails[], double bid)
{
  double firstLargeRedBarDistance = barDetails[4].open - barDetails[4].close;
  double secondLargeRedBarDistance = barDetails[3].open - barDetails[3].close;
  double thirdLargeRedBarDistance = barDetails[2].open - barDetails[2].close;
  double barBeforeFirstLargeGreenBarDistance = barDetails[5].open - barDetails[5].close;
  if (barBeforeFirstLargeGreenBarDistance < 0)
  {
    barBeforeFirstLargeGreenBarDistance = barDetails[5].close - barDetails[5].open;
  }

  //For easier debugging of which statement is incorrect
  if (currentTime == "2019.05.14 05:09")
  {
    Alert("Debugging Time");
  }

  //Check bars are correct type
  if (firstLargeRedBarDistance <= 0 || secondLargeRedBarDistance <= 0 || thirdLargeRedBarDistance <= 0)
  {
    return false;
  }

  //third red bar close must be X below second red close, second red close must be X below first red close
  //AND third red bar open must be X below second red open, second red open must be X below first red open
  if (!(barDetails[2].close < (barDetails[3].close + (closeDistance * _Point))) || !(barDetails[3].close < (barDetails[4].close + (closeDistance * _Point))) ||
      !(barDetails[2].open < (barDetails[3].open + (openDistance * _Point))) || !(barDetails[3].close < (barDetails[4].close + (openDistance * _Point))))
  {
    return false;
  }

  //Bars must be X number of points
  if ((firstLargeRedBarDistance < (minPoints * _Point)) || (secondLargeRedBarDistance < (minPoints * _Point)) || (thirdLargeRedBarDistance < (minPoints * _Point)))
  {
    return false;
  }

  //Wicks must be < than Xth of Bar
  if (barWickSize > 0)
  {
    if (!((barDetails[4].high - barDetails[4].open) < (firstLargeRedBarDistance / barWickSize)) ||
        !((barDetails[4].close - barDetails[4].low) < (firstLargeRedBarDistance / barWickSize)) ||
        !((barDetails[3].high - barDetails[3].open) < (secondLargeRedBarDistance / barWickSize)) ||
        !((barDetails[3].close - barDetails[3].low) < (secondLargeRedBarDistance / barWickSize)) ||
        !((barDetails[2].high - barDetails[2].open) < (thirdLargeRedBarDistance / barWickSize)) ||
        !((barDetails[2].close - barDetails[2].low) < (thirdLargeRedBarDistance / barWickSize)))
    {
      return false;
    }
  }

  //Conf bar must be Red bar
  if (waitForConfBar == true && (barDetails[1].open - barDetails[1].close) <= 0)
  {
    return false;
  }

  //Take position after price has reached Final Red candles close - X points
  if (takePositionThreshold > 0 && !(bid >= (barDetails[2].low - (takePositionThreshold * _Point))))
  {
    return false;
  }

  return true;
}

void GetTrades()
{
  datetime to = TimeCurrent();
  datetime from = to - (PeriodSeconds(PERIOD_D1) * 7); //check deals for the past 7 days
  ResetLastError();
  if (!HistorySelect(0, to))
  {
    Print(__FUNCTION__, " HistorySelect=false. Error code=", GetLastError());
  }
  
  int totalDeals = HistoryDealsTotal();
  long ticket = 0;
  double   price;
  double   profit;
  datetime time;
  string   symbol;
  long     type;
  long     entry;
  
  for (int i = 0; i < totalDeals; i++)
  {
    if((ticket=HistoryDealGetTicket(i))>0)
    {
      price =HistoryDealGetDouble(ticket,DEAL_PRICE);
      time  =(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      symbol=HistoryDealGetString(ticket,DEAL_SYMBOL);
      type  =HistoryDealGetInteger(ticket,DEAL_TYPE);
      entry =HistoryDealGetInteger(ticket,DEAL_ENTRY);
      profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      
      ENUM_ORDER_REASON reason = HistoryDealGetInteger(ticket, DEAL_REASON);
      
      if (EnumToString(reason) == "DEAL_REASON_SL")
      {
        Print("STOP LOSS HIT: ticket ", ticket, "  triggered SL");
      }
      else if (EnumToString(reason) == "DEAL_REASON_TP")
      {  
        Print("TAKE PROFIT HIT: ticket ", ticket, "  triggered TP");
      }
      else
      {  
        Print("OTHER ticket ", ticket, "  triggered OTHER");
      }
    }
  }
}

MqlTradeResult MakeLongTrade(MqlTradeRequest &tradeRequest, MqlTradeResult &tradeResult, double bid)
{
  tradeRequest.action = TRADE_ACTION_DEAL; // immediate order execution

  tradeRequest.sl = NormalizeDouble(bid - stopLoss * _Point, _Digits);

  tradeRequest.tp = NormalizeDouble(bid + takeProfit * _Point, _Digits);

  tradeRequest.symbol = _Symbol;                 // currency pair
  tradeRequest.volume = lotSize;                 // number of lots to trade
  tradeRequest.magic = expertAdvisorMagicNumber; // Order Magic Number
  tradeRequest.type = ORDER_TYPE_BUY;            // Buy Order
  tradeRequest.type_filling = ORDER_FILLING_FOK; // Order execution type
  tradeRequest.deviation = 10;
  
  tradeRequest.comment = "STOCH_K: " + stoch_K[0] + " :: STOCH_D: " + stoch_D[0];
  
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}

MqlTradeResult MakeShortTrade(MqlTradeRequest &tradeRequest, MqlTradeResult &tradeResult, double ask)
{
  tradeRequest.action = TRADE_ACTION_DEAL;

  tradeRequest.sl = NormalizeDouble(ask + stopLoss * _Point, _Digits);

  tradeRequest.tp = NormalizeDouble(ask - takeProfit * _Point, _Digits);

  tradeRequest.symbol = _Symbol;                 // currency pair
  tradeRequest.volume = lotSize;                 // number of lots to trade
  tradeRequest.magic = expertAdvisorMagicNumber; // Order Magic Number
  tradeRequest.type = ORDER_TYPE_SELL;           // Buy Order
  tradeRequest.type_filling = ORDER_FILLING_FOK; // Order execution type
  tradeRequest.deviation = 10;
  
  tradeRequest.comment = "STOCH_K: " + stoch_K[0] + " :: STOCH_D: " + stoch_D[0];
  
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}