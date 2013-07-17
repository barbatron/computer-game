/**
 * Class: DeferredQueue
 * Version: 1.0
 * 
 * Utility class to queue multiple jQuery Deferreds and add events to the execution flow
 * 
 * License: MIT-style license.
 * Copyright: Copyright (c) 2013 HarmenM | Syslogic
 */
var DeferredQueue = (function () {
    /**
     * Class: _Chain
     */
    var _Chain = (function (callback) {
        var self = this,
            _queue = jQuery.Deferred(),
            _promise = _queue.promise(),

            _callbackHandlers = {
                'start': null,
                'complete': null,
                'failed': null
            };

        /**
         * Function: add
         * 
         * Parameters:
         *  callback Function - the callback function
         * 
         * Returns: _Chain - this for chaining
         */
        this.add = function (callback) {
            if (_queue.state() !== "pending") {
                throw "Cannot add callbacks when the chain is already fired";
            }

            _promise = _promise.pipe(callback);

            return self;
        };

        /**
         * Function: on
         * 
         * Parameters:
         *  eventName string - The name of the event to add a callback for
         *  callback Function - the callback function
         * 
         * Returns: _Chain - this for chaining
         */
        this.on = function (eventName, callback) {
            if (_callbackHandlers[eventName] === undefined) {
                throw "The event '" + eventName + "' is not a valid callback for the queue item";
            }
            else if (_callbackHandlers[eventName] === null) {
                _callbackHandlers[eventName] = jQuery.Callbacks("once");
            }

            _callbackHandlers[eventName].add(callback);

            return self;
        };

        /**
         * Function: trigger
         * 
         * Parameters:
         *  eventName string - The name of the event to trigger the callbacks for
         * 
         * Returns: _Chain - this for chaining
         */
        this.trigger = function (eventName) {
            if (_callbackHandlers[eventName] === undefined) {
                throw "Invalid callback handler name specified";
            }
            else if (_callbackHandlers[eventName] !== null) {
                _callbackHandlers[eventName].fire();
            }
        };

        /**
         * Function: run
         * 
         * Runs the Chain
         * 
         * Parameters:
         *  endCallback Function - the callback function
         */
        this.run = function (endCallback) {
            _promise = _promise.always(endCallback.bind(null, self));

            self.trigger('start');

            _queue.resolve();
        };
    }),

    _queue = [],
    _pending = false,

    _callQueue = function () {
        if (_pending === true || _queue.length <= 0) {
            return;
        }

        _pending = true;
        setTimeout(_queue[0].run.bind(null, _onAfterChainFinished), 0);
    },

    _onAfterChainFinished = function (chain, promise) {
        if (promise != null && promise.state !== undefined) {
            switch (promise.state()) {
                case "resolved":
                    chain.trigger("complete");
                    break;
                case "rejected":
                    chain.trigger("failed");
                    break;
            }
        }
        else {
            chain.trigger("complete");
        }

        _queue.shift();
        _pending = false;

        _callQueue();
    };

    /**
     * Function: chain
     * 
     * Create a Deferred Chain
     * 
     * Returns: _Chain
     */
    this.chain = function (callback) {
        var chain = new _Chain();

        if (callback !== undefined) {
            chain.add(callback);
        }

        _queue.push(chain);
        _callQueue();

        return chain;
    };
});
