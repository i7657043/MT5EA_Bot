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
input double babyBarOverallSizeArg=2;   //Outer bars must be X times the size of the baby bar
input double outerBoundaryThreshold=5;  //Lower number = tighter outer boundaries
input int minPoints=0;                  //Outer bars must be spread > X number of points
input double barWickSize=0;             //Wicks must be X times smaller than their bodies


input double takePositionThreshold=2;   //Enter after price = final bar close + X points
input bool waitForConfBar = true;       //Wait for Conf bar
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

  //--- Get the last price quote using the MQL5 MqlTick Structure
  if (!SymbolInfoTick(_Symbol, latestPriceDetails))
  {
    Alert("Error getting the latest price quote - error:", GetLastError(), "!!");
    return;
  }

  //--- Get the details of the latest 5 bars and MA
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

  //--- Get the details of the latest 5 volumes
  CopyBuffer(iVolumes(_Symbol, _Period, VOLUME_TICK), 0, 0, 6, volume);

  //--- Get the details of the latest 5 volumes
  CopyBuffer(iRSI(_Symbol, _Period, 14, PRICE_CLOSE), 0, 0, 6, rsi);

  //--- We have no errors, so continue to trading

  Comment("Volume of Current bar: " + volume[0] +
          "\nVolume of Current bar -1: " + volume[1] +
          "\nVolume of Current bar -2: " + volume[2]);

  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  int spread = (int)MathRound((ask - bid) / SymbolInfoDouble(Symbol(), SYMBOL_POINT));

  if (makeLongTrades == true && tradeBarCounterActive == false && positionTakenThisBar == false && CheckForLong3BarPlay(barDetails, ask))
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
  

  //if (makeShortTrades == true && tradeBarCounterActive == false && positionTakenThisBar == false)
  //{
  //  if (weirdRevertShort == true)
  //  {
  //    tradeResult = MakeLongTrade(tradeRequest, tradeResult, bid);
  //  }
  //  else
  //  {
  //    tradeResult = MakeShortTrade(tradeRequest, tradeResult, ask);
  //  }

  //  if (tradeResult.retcode == 10009 || tradeResult.retcode == 10008) //Request is completed or order placed
  //  {
  //    positionTakenThisBar = true;
  //    tradeBarCounterActive = true;
  //    Alert("A Sell order at bid price: ", bid, " has been successfully placed with Ticket#:", tradeResult.order, "!!");
  //  }
  //  else
  //  {
  //    if (weirdRevertShort == true)
  //    {
  //      Alert("The Sell (BUY) order request (price: " + ask + ") could not be completed -error:", GetLastError());
  //    }
  //    else
  //    {
  //      Alert("The Sell order request (price: " + bid + ") could not be completed -error:", GetLastError());
  //    }

  //    ResetLastError();
  //    return;
  //}
  }

  isNewBar = false;
}

bool CheckForLong3BarPlay(MqlRates &barDetails[], double ask)
{
  double firstLargeGreenBarDistance = barDetails[3].close - barDetails[3].open;
  double secondBabyRedBarDistance = barDetails[2].open - barDetails[2].close;
  double thirdLargeGreenBarDistance = barDetails[1].close - barDetails[1].open;
  double barBeforeFirstLargeGreenBarDistance = barDetails[4].close - barDetails[4].open;
  if (barBeforeFirstLargeGreenBarDistance < 0)
  {
   barBeforeFirstLargeGreenBarDistance = barDetails[4].open - barDetails[4].close;
  }
  
  //For easier debugging of which statement is incorrect
  if (currentTime == "2018.09.25 02:15")
  {
    Alert("Debugging Time");
  }  
  
  //Check bars are correct type, baby red can be Doji bar
  if (firstLargeGreenBarDistance <= 0 || thirdLargeGreenBarDistance <= 0 || secondBabyRedBarDistance < 0)  
  {
    return false;
  }
  
  //Outer green bars must be X number of points
  if ((firstLargeGreenBarDistance < (minPoints * _Point)) || (thirdLargeGreenBarDistance < (minPoints * _Point)))
  {
   return false;
  }  
  
  //baby red bar cant be above or below outer green bars
  if ((barDetails[2].high >  barDetails[1].high) || (barDetails[2].high >  barDetails[3].high) ||
      (barDetails[2].low <  barDetails[1].low) || (barDetails[2].low <  barDetails[3].low))  
  {
    return false;
  }
  
  //third green bar close must be above first green close and third green bar open must be above first green open
  if (!(barDetails[1].close >  barDetails[3].close) && !(barDetails[1].open >  barDetails[3].open))  
  {
    return false;
  } 
  
  
  //Outer bars must be X times the size of the baby bar
  if (!(firstLargeGreenBarDistance > (secondBabyRedBarDistance * babyBarOverallSizeArg)) ||
      !(thirdLargeGreenBarDistance > (secondBabyRedBarDistance * babyBarOverallSizeArg)))
  {
    return false;
  }
  
  //Wicks must be X times smaller than their bodies  
  //if (barWickSize > 0 && (!((barDetails[3].high - barDetails[3].close) < (firstLargeGreenBarDistance / barWickSize)) ||
  //                        !((barDetails[3].open - barDetails[3].low) < (firstLargeGreenBarDistance / barWickSize))   ||
  //                        !((barDetails[1].high - barDetails[1].close) < (thirdLargeGreenBarDistance / barWickSize)) ||
  //                        !((barDetails[1].open - barDetails[1].low) < (thirdLargeGreenBarDistance / barWickSize))))
  //{
  //  return false;
  //}
  
  
  //Top of baby red bar must be below top Xth of third green bar
  //And
  //Bottom of baby red bar must be above bottom Xth of first green bar
  //This Rule makes sure outer green bars totally surround BODY of baby red, but not Wick
  if (!(barDetails[2].open <= (barDetails[1].close - (thirdLargeGreenBarDistance / outerBoundaryThreshold))) ||
      !(barDetails[2].close >= (barDetails[3].open + (firstLargeGreenBarDistance / outerBoundaryThreshold))))
  {
   return false;
  }
  
  //Conf bar must be Green bar //Can only have this if getting 6 bars
  //if (waitForConfBar == true && (barDetails[1].close - barDetails[1].open) < 0)
  //{
  //  return false;
  //}
    
  //Take position after price has reached Final Green candles close + X points
  if (takePositionThreshold > 0 && !(ask <= (barDetails[1].high + (takePositionThreshold * _Point))))
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
  
  tradeRequest.comment = "";
  
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
  
  tradeRequest.comment = "";
  
  OrderSend(tradeRequest, tradeResult);

  return tradeResult;
}