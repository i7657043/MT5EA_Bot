//+------------------------------------------------------------------+
//|                                                     3BarPlay.mq5 |
//|                                                               JG |
//|                                                             None |
//+------------------------------------------------------------------+
//--- input parameters
input int stopLoss = 30;
input int takeProfit = 5;
input int movingAveragePeriod = 8;
input int expertAdvisorMagicNumber = 12345; // EA Magic Number
input double lotSize = 0.1;                 // lots to Trade

//--- Other parameters
int movingAverageHandler; // handle for our Moving Average indicator
double movingAverages[];  // Dynamic array to hold the values of Moving Average for each bars
int STP, TKP;             // To be used for Stop Loss & Take Profit values

int OnInit()
{
  //--- Get the handle for Moving Average indicator
  movingAverageHandler = iMA(_Symbol, _Period, movingAveragePeriod, 0, MODE_EMA, PRICE_CLOSE);

  //--- What if handle returns Invalid Handle
  if (movingAverageHandler < 0)
  {
    Alert("Error Creating Handles for indicators - error: ", GetLastError(), "!!");
  }

  STP = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
  TKP = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

  //if (_Digits == 5 || _Digits == 3)
  //{
  //  STP = STP * 10;
  //  TKP = TKP * 10;
  //}

  return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
  IndicatorRelease(movingAverageHandler);
}

void OnTick()
{
  //--- Do we have enough bars to work with
  // int Mybars = Bars(_Symbol, _Period);
  // if (Mybars < 60) // if total bars is less than 60 bars
  // {
  //   Alert("We have less than 60 bars, EA will now exit!!");
  //   return;
  // }

  // We will use the static oldTime variable to serve the bar time.
  // At each OnTick execution we will check the current bar time with the saved one.
  // If the bar time isn't equal to the saved time, it indicates that we have a new tick.
  static datetime oldTime;
  datetime newTime[1];

  bool isNewBar = false;
  bool positionTakenThisBar=false;

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
    }
  }
  else
  {
    Alert("Error in copying historical times data, error =", GetLastError());
    ResetLastError();
    return;
  }

  //--- EA should only check for new trade if we have a new bar
  //if (isNewBar == false)
  //{
  //  return;
  //}  

  //--- Define some MQL5 Structures we will use for our trade
  MqlTick latestPriceDetails;   // To be used for getting recent/latest price quotes
  MqlTradeRequest tradeRequest; // To be used for sending our trade requests
  MqlTradeResult tradeResult;   // To be used to get our trade results
  MqlRates barDetails[];        // To be used to store the prices, volumes and spread of each bar
  ZeroMemory(tradeRequest);     // Initialization of tradeRequest structure

  /*
      Let's make sure our arrays values for the Rates and MA values 
      is store serially similar to the timeseries array
      */
  // the bar details arrays
  ArraySetAsSeries(barDetails, true);
  // the MA-8 values arrays
  ArraySetAsSeries(movingAverages, true);

  //--- Get the last price quote using the MQL5 MqlTick Structure
  if (!SymbolInfoTick(_Symbol, latestPriceDetails))
  {
    Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
    return;
  }

  //--- Get the details of the latest 3 bars and MA
  if (CopyRates(_Symbol, _Period, 0, 3, barDetails) < 0)
  {
    Alert("Error copying rates/history data - error:", GetLastError(), "!!");
    return;
  }
  if (CopyBuffer(movingAverageHandler, 0, 0, 3, movingAverages) < 0)
  {
    Alert("Error copying Moving Average indicator buffer - error:", GetLastError());
    return;
  }

  //--- We have no errors, so continue to trading

  //--- Do we have positions opened already? //ToDo: improve this to check more strictly
  bool buy_opened = false;
  bool sell_opened = false;
  
  if (PositionSelect(_Symbol) == true) // we have an opened position
  {
    if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
      buy_opened = true;
    }
    else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
    {
      sell_opened = true;
    }
  }

  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  int spread = (int)MathRound((ask - bid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT));

  Comment(
      "Current bar OPEN:" + barDetails[0].open +
      "\nCurrent bar -1 OPEN:" + barDetails[1].open +
      "\nCurrent bar -2 OPEN:" + barDetails[2].open +
      "\n\nCurrent bar CLOSE:" + barDetails[0].close +
      "\nCurrent bar -1 CLOSE:" + barDetails[1].close +
      "\nCurrent bar -2 CLOSE:" + barDetails[2].close +
      "\n\nCurrent bar HIGH:" + barDetails[0].high +
      "\nCurrent bar -1 HIGH:" + barDetails[1].high +
      "\nCurrent bar -2 HIGH:" + barDetails[2].high +
      "\n\nCurrent bar LOW:" + barDetails[0].low +
      "\nCurrent bar -1 LOW:" + barDetails[1].low +
      "\nCurrent bar -2 LOW:" + barDetails[2].low +
      "\n\nCurrent Buy Price:" + ask +
      "\nCurrent Sell Price:" + bid +
      "\n\nCurrent Spread:" + spread);

  // previous price closed above MA-8
  //bool buyCondition1 = (latestPriceDetails.bid > movingAverages[1]);

  bool buyCondition1 = CheckForLong3BarPlay(barDetails);

  if (buyCondition1 && positionTakenThisBar == false)
  {
    // any already opened Buy position?
    //if (buy_opened)
    //{
    //  Alert("We already have a Buy Position!!!");
    //  return; // Don't open a new Buy Position
    //}

    tradeResult = MakeLongTrade(tradeRequest, tradeResult, bid, ask);

    if (tradeResult.retcode == 10009 || tradeResult.retcode == 10008) //Request is completed or order placed
    {
      Alert("A Buy order at bid price: ", bid, " has been successfully placed with Ticket#:", tradeResult.order, "!!");
      Sleep(10000);
    }
    else
    {
      Alert("The Buy order request could not be completed -error:", GetLastError());
      ResetLastError();
      return;
    }

    positionTakenThisBar = true;
  }

  // previous price closed below MA-8
  //bool sellCondition1 = (latestPriceDetails.ask < movingAverages[1]);

  bool buyCondition1 = CheckForShort3BarPlay(barDetails);

  if (sellCondition1 && positionTakenThisBar == false)
  {
    // any already opened Sell position?
    //if (sell_opened)
    //{
    //  Alert("We already have a Sell Position!!!");
    //  return; // Don't open a new Sell Position
    //}

    tradeResult = MakeShortTrade(tradeRequest, tradeResult, bid, ask);

    if (tradeResult.retcode == 10009 || tradeResult.retcode == 10008) //Request is completed or order placed
    {
      Alert("A Sell order at ask price:", ask, " has been successfully placed with Ticket#:", tradeResult.order, "!!");
      Sleep(10000);
    }
    else
    {
      Alert("The Sell order request could not be completed -error:", GetLastError());
      ResetLastError();
      return;
    }

    positionTakenThisBar = true;
  }
}

bool CheckForLong3BarPlay(MqlRates barDetails[])
{
  double firstLargeGreenBarDistance = barDetails[2].close - barDetails[2].open;
  double secondBabyRedBarDistance = barDetails[1].open - barDetails[1].close;
  double thirdLargeGreenBarDistance = barDetails[0].close - barDetails[0].open;  

  return firstLargeGreenBarDistance > (secondBabyRedBarDistance * 2.5) && 
  barDetails[1].close <= (barDetails[2].close - (firstLargeGreenBarDistance / 5))  &&
  barDetails[1].open <= (barDetails[0].open + (thirdLargeGreenBarDistance / 5))  &&
  thirdLargeGreenBarDistance > (secondBabyRedBarDistance * 2);
}

bool CheckForShort3BarPlay(MqlRates barDetails[])
{
  double firstLargeGreenBarDistance = barDetails[2].open - barDetails[2].close;
  double secondBabyRedBarDistance = barDetails[1].close - barDetails[1].open;
  double thirdLargeGreenBarDistance = barDetails[0].open - barDetails[0].close;  

  return firstLargeGreenBarDistance > (secondBabyRedBarDistance * 2.5) && 
  barDetails[1].open <= (barDetails[2].open - (firstLargeGreenBarDistance / 5))  &&
  barDetails[1].close <= (barDetails[0].close + (thirdLargeGreenBarDistance / 5))  &&
  thirdLargeGreenBarDistance > (secondBabyRedBarDistance * 2);
}

MqlTradeResult MakeLongTrade(MqlTradeRequest &tradeRequest, MqlTradeResult &tradeResult, double bid, double ask)
{
  tradeRequest.action = TRADE_ACTION_DEAL; // immediate order execution

  tradeRequest.sl = NormalizeDouble(bid - STP * _Point, _Digits);
  tradeRequest.tp = NormalizeDouble(bid + TKP * _Point, _Digits);

  tradeRequest.symbol = _Symbol;                 // currency pair
  tradeRequest.volume = lotSize;                 // number of lots to trade
  tradeRequest.magic = expertAdvisorMagicNumber; // Order Magic Number
  tradeRequest.type = ORDER_TYPE_BUY;            // Buy Order
  tradeRequest.type_filling = ORDER_FILLING_FOK; // Order execution type
  tradeRequest.deviation = 10;
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}

MqlTradeResult MakeShortTrade(MqlTradeRequest &tradeRequest, MqlTradeResult &tradeResult, double bid, double ask)
{
  tradeRequest.action = TRADE_ACTION_DEAL;

  tradeRequest.sl = NormalizeDouble(ask + STP * _Point, _Digits);
  tradeRequest.tp = NormalizeDouble(ask - TKP * _Point, _Digits);

  tradeRequest.symbol = _Symbol;                 // currency pair
  tradeRequest.volume = lotSize;                 // number of lots to trade
  tradeRequest.magic = expertAdvisorMagicNumber; // Order Magic Number
  tradeRequest.type = ORDER_TYPE_SELL;           // Buy Order
  tradeRequest.type_filling = ORDER_FILLING_FOK; // Order execution type
  tradeRequest.deviation = 10;
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}