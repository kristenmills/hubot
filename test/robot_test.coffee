# Assertions and Stubbing
chai = require 'chai'
sinon = require 'sinon'
chai.use require 'sinon-chai'

{ expect } = chai

mockery = require 'mockery'

# Hubot classes
Robot = require '../src/robot.coffee'
{ CatchAllMessage, EnterMessage, LeaveMessage, TextMessage, TopicMessage } = require '../src/message'
Adapter = require '../src/adapter'

# Preload the Hubot mock adapter but substitute in the latest version of Adapter
mockery.enable()
mockery.registerAllowable 'hubot-mock-adapter'
mockery.registerAllowable 'lodash' # hubot-mock-adapter uses lodash
# Force hubot-mock-adapter to use the latest version of Adapter
mockery.registerMock 'hubot/src/adapter', Adapter
# Load the mock adapter into the cache
require 'hubot-mock-adapter'
# We're done with mockery
mockery.deregisterMock 'hubot/src/adapter'
mockery.disable()


describe 'Robot', ->
  beforeEach ->
    @robot = new Robot null, 'mock-adapter', yes, 'TestHubot'
    @robot.run

    @user = @robot.brain.userForId '1', {
      name: 'hubottester'
      room: '#mocha'
    }

  afterEach ->
   @robot.server.close()
   @robot.shutdown()

  describe 'Unit Tests', ->
    describe '#listen', ->
      it 'registers a new listener', ->
        expect(@robot.listeners).to.have.length(0)
        @robot.hear /.*/, () ->
        expect(@robot.listeners).to.have.length(1)

    describe '#hear', ->
      it 'registers a new listener', ->
        sinon.spy @robot, 'listen'
        @robot.hear /.*/, () ->
        expect(@robot.listen).to.have.been.called

    describe '#respond', ->
      it 'registers a new listener', ->
        sinon.spy @robot, 'listen'
        @robot.respond /.*/, () ->
        expect(@robot.listen).to.have.been.called

    describe '#enter', ->
      it 'registers a new listener', ->
        sinon.spy @robot, 'listen'
        @robot.enter () ->
        expect(@robot.listen).to.have.been.called

    describe '#leave', ->
      it 'registers a new listener', ->
        sinon.spy @robot, 'listen'
        @robot.leave () ->
        expect(@robot.listen).to.have.been.called

    describe '#topic', ->
      it 'registers a new listener', ->
        sinon.spy @robot, 'listen'
        @robot.topic () ->
        expect(@robot.listen).to.have.been.called

    describe '#catchAll', ->
      it 'registers a new listener', ->
        sinon.spy @robot, 'listen'
        @robot.catchAll () ->
        expect(@robot.listen).to.have.been.called

    describe '#receive', ->
      it 'calls all registered listeners', ->
        # Need to use a real Message so that the CatchAllMessage constructor works
        testMessage = new TextMessage(@user, 'message123')

        listener =
          call: sinon.spy()

        @robot.listeners = [
          listener
          listener
          listener
          listener
        ]

        @robot.receive testMessage

        # When no listeners match, each listener is called twice: once with
        # the original message and once with a CatchAll message
        expect(listener.call).to.have.callCount(8)

      it 'sends a CatchAllMessage if no listener matches', ->
        # Testing for recursion with a new CatchAllMessage that wraps the
        # original message

        testMessage = new TextMessage(@user, 'message123')
        @robot.listeners = []

        # Replace @robot.receive so we can catch when the functions recurses
        oldReceive = @robot.receive
        @robot.receive = (message) ->
          expect(message).to.be.instanceof(CatchAllMessage)
          expect(message.message).to.be.equal(testMessage)
        sinon.spy(@robot, 'receive')

        # Call the original receive method that we want to test
        oldReceive.call @robot, testMessage

        # Ensure the function recursed
        expect(@robot.receive).to.have.been.called

      it 'does not trigger a CatchAllMessage if a listener matches', ->
        testMessage = new TextMessage(@user, 'message123')

        matchingListener =
          call: (message) ->
            # indicate that the message matched the listener
            true

        # Replace @robot.receive so we can catch if the functions recurses
        oldReceive = @robot.receive
        @robot.receive = sinon.spy()

        @robot.listeners = [
          matchingListener
        ]

        # Call the original receive method that we want to test
        oldReceive.call @robot, testMessage

        # Ensure the function did not recurse
        expect(@robot.receive).to.not.have.been.called

      it 'stops processing if a listener marks the message as done', ->
        testMessage = new TextMessage(@user, 'message123')

        matchingListener =
          call: (message) ->
            message.done = true
            # Listener must have matched
            true

        listenerSpy =
          call: sinon.spy()

        @robot.listeners = [
          matchingListener
          listenerSpy
        ]

        @robot.receive testMessage

        expect(listenerSpy.call).to.not.have.been.called

      it 'gracefully handles listener uncaughtExceptions (move on to next listener)', ->
        testMessage = {}
        theError = new Error()

        badListener =
          call: () ->
            throw theError

        goodListenerCalled = false
        goodListener =
          call: (_) ->
            goodListenerCalled = true
            true

        @robot.listeners = [
          badListener
          goodListener
        ]

        @robot.emit = (name, err, response) ->
          expect(name).to.equal('error')
          expect(err).to.equal(theError)
          expect(response.message).to.equal(testMessage)
        sinon.spy(@robot, 'emit')

        @robot.receive testMessage

        expect(@robot.emit).to.have.been.called
        expect(goodListenerCalled).to.be.ok

  describe 'Listener Registration', ->
    describe '#listen', ->
      it 'forwards the matcher and callback to Listener', ->
        callback = sinon.spy()
        matcher = sinon.spy()

        @robot.listen(matcher, callback)
        testListener = @robot.listeners[0]

        expect(testListener.matcher).to.equal(matcher)
        expect(testListener.callback).to.equal(callback)

    describe '#hear', ->
      it 'matches TextMessages', ->
        callback = sinon.spy()
        testMessage = new TextMessage(@user, 'message123')
        testRegex = /^message123$/

        @robot.hear(testRegex, callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.be.ok

      it 'does not match EnterMessages', ->
        callback = sinon.spy()
        testMessage = new EnterMessage(@user)
        testRegex = /.*/

        @robot.hear(testRegex, callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.not.be.ok

    describe '#respond', ->
      it 'matches TextMessages addressed to the robot', ->
        callback = sinon.spy()
        testMessage = new TextMessage(@user, 'TestHubot message123')
        testRegex = /message123$/

        @robot.respond(testRegex, callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.be.ok

      it 'does not match EnterMessages', ->
        callback = sinon.spy()
        testMessage = new EnterMessage(@user)
        testRegex = /.*/

        @robot.respond(testRegex, callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.not.be.ok

    describe '#enter', ->
      it 'matches EnterMessages', ->
        callback = sinon.spy()
        testMessage = new EnterMessage(@user)

        @robot.enter(callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.be.ok

      it 'does not match TextMessages', ->
        callback = sinon.spy()
        testMessage = new TextMessage(@user, 'message123')

        @robot.enter(callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.not.be.ok

    describe '#leave', ->
      it 'matches LeaveMessages', ->
        callback = sinon.spy()
        testMessage = new LeaveMessage(@user)

        @robot.leave(callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.be.ok

      it 'does not match TextMessages', ->
        callback = sinon.spy()
        testMessage = new TextMessage(@user, 'message123')

        @robot.leave(callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.not.be.ok

    describe '#topic', ->
      it 'matches TopicMessages', ->
        callback = sinon.spy()
        testMessage = new TopicMessage(@user)

        @robot.topic(callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.be.ok

      it 'does not match TextMessages', ->
        callback = sinon.spy()
        testMessage = new TextMessage(@user, 'message123')

        @robot.topic(callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.not.be.ok

    describe '#catchAll', ->
      it 'matches CatchAllMessages', ->
        callback = sinon.spy()
        testMessage = new CatchAllMessage(new TextMessage(@user, 'message123'))

        @robot.catchAll(callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.be.ok

      it 'does not match TextMessages', ->
        callback = sinon.spy()
        testMessage = new TextMessage(@user, 'message123')

        @robot.catchAll(callback)
        testListener = @robot.listeners[0]
        result = testListener.matcher(testMessage)

        expect(result).to.not.be.ok

  describe 'Message Processing', ->
    it 'calls a matching listener', (done) ->
      testMessage = new TextMessage(@user, 'message123')
      @robot.hear /^message123$/, (response) ->
        expect(response.message).to.equal(testMessage)
        done()
      @robot.receive testMessage

    it 'calls multiple matching listeners', ->
      testMessage = new TextMessage(@user, 'message123')

      listenersCalled = 0
      listenerCallback = (response) ->
        expect(response.message).to.equal(testMessage)
        listenersCalled++

      @robot.hear /^message123$/, listenerCallback
      @robot.hear /^message123$/, listenerCallback

      @robot.receive testMessage

      expect(listenersCalled).to.equal(2)

    it 'calls the catch-all listener if no listeners match', (done) ->
      testMessage = new TextMessage(@user, 'message123')

      listenerCallback = sinon.spy()
      @robot.hear /^no-matches$/, listenerCallback

      @robot.catchAll (response) ->
        expect(listenerCallback).to.not.have.been.called
        expect(response.message).to.equal(testMessage)
        done()

      @robot.receive testMessage

    it 'does not call the catch-all listener if any listener matched', ->
      testMessage = new TextMessage(@user, 'message123')

      listenerCallback = sinon.spy()
      @robot.hear /^message123$/, listenerCallback

      catchAllCallback = sinon.spy()
      @robot.catchAll catchAllCallback

      @robot.receive testMessage

      expect(listenerCallback).to.have.been.called.once
      expect(catchAllCallback).to.not.have.been.called

    it 'stops processing if message.finish() is called synchronously', ->
      testMessage = new TextMessage(@user, 'message123')

      @robot.hear /^message123$/, (response) ->
        response.message.finish()

      listenerCallback = sinon.spy()
      @robot.hear /^message123$/, listenerCallback

      @robot.receive testMessage

      expect(listenerCallback).to.not.have.been.called

    it 'calls non-TextListener objects', (done) ->
      testMessage = new EnterMessage @user

      @robot.enter (response) ->
        expect(response.message).to.equal(testMessage)
        done()

      @robot.receive testMessage
