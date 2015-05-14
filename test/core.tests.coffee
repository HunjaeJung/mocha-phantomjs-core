describe 'mocha-phantomjs-core', ->

  chai = require 'chai'
  expect = chai.expect
  should = chai.should()
  spawn = require('child_process').spawn
  url = require('url')
  fs = require('fs')
  Promise = require('bluebird')

  fileURL = (file) ->
    fullPath = fs.realpathSync "#{process.cwd()}/test/#{file}.html"
    fullPath = fullPath.replace /\\/g, '\/'
    urlString = fullPath
    urlString = url.format { protocol: 'file', hostname: '', pathname: fullPath } if process.platform isnt 'win32'

  run = (opts) ->
    opts = opts or {}
    new Promise (resolve, reject) ->          
      stdout = ''
      stderr = ''
      spawnArgs = [
        "#{process.cwd()}/mocha-phantomjs-core.js",
        opts.url or fileURL(opts.test or 'passing'),
        opts.reporter or 'spec',
        JSON.stringify(opts)
      ]
      spawnArgs = [spawnArgs[0]] if opts.noargs
      console.log spawnArgs.join ' '
      mochaPhantomJS = spawn "#{process.cwd()}/phantomjs", spawnArgs
      mochaPhantomJS.stdout.on 'data', (data) -> stdout = stdout.concat data.toString()
      mochaPhantomJS.stderr.on 'data', (data) -> stderr = stderr.concat data.toString()
      mochaPhantomJS.on 'exit', (code) ->
        resolve { code, stdout, stderr }
      mochaPhantomJS.on 'error', (err) -> reject err


  it 'returns a failure code and shows usage when no args are given', ->
    { code, stdout } = yield run { noargs: true }
    code.should.equal 255
    stdout.should.contain 'Usage: phantomjs mocha-phantomjs-core.js URL REPORTER [CONFIG-AS-JSON]'

  it 'returns a failure code and notifies of bad url when given one', ->
    @timeout = 4000
    { code, stderr } = yield run { url: 'foo/bar.html' }
    code.should.equal 1
    stderr.should.match /failed to load the page/i
    stderr.should.match /check the url/i
    stderr.should.match /foo\/bar.html/i

  # https://github.com/ariya/phantomjs/issues/12973
  it 'returns a failure code and notifies of no such runner class', !process.env.PHANTOMJS2 and ->
    { code, stderr } = yield run { reporter: 'nonesuch' }
    code.should.equal 1
    stderr.should.match /Unable to open file 'nonesuch'/

  it 'returns a success code when a directory exists with the same name as a built-in runner', ->
    fs.mkdir 'spec'
    { code } = yield run()
    fs.rmdir 'spec'
    code.should.equal 0

  it 'returns a failure code when mocha can not be found on the page', ->
    { code, stderr } = yield run { test: 'blank' }
    code.should.equal 1
    stderr.should.match /Failed to run any tests/

  it 'returns a failure code when mocha fails to start for any reason', ->
    { code, stderr } = yield run { test: 'bad' }
    code.should.equal 1
    stderr.should.match /Failed to run any tests/

  it 'returns a failure code when mocha is not started in a timely manner', ->
    { code, stderr } = yield run { test: 'timeout', timeout: 500 }
    code.should.not.equal 0
    stderr.should.match /Failed to run any tests/

  it 'returns a failure code when there is a page error', ->
    { code, stderr } = yield run { test: 'error' }
    code.should.equal 1
    stderr.should.match /ReferenceError/

  it 'does not fail when an iframe is used', ->
    { code, stdout, stderr } = yield run { test: 'iframe' }
    stderr.should.not.match /Failed to load the page\./m
    stdout.should.not.match /Failed to load the page\./m
    code.should.equal 0

  it 'returns the mocha runner from run() and allows modification of it', ->
    { code, stdout } = yield run { test: 'mocha-runner' }
    stdout.should.not.match /Failed via an Event/m
    code.should.equal 1

  it 'passes the arguments along to mocha.run', ->
    { stdout } = yield run { test: 'mocha-runner' }
    stdout.should.match /Run callback fired/m

  it 'can use a different reporter', ->
    { stdout } = yield run
      reporter: 'xunit'
      test: 'mixed'
    
    stdout.should.match /<testcase classname="Tests Mixed" name="passes 1" time=".*"\/>/

  describe 'exit code', ->
    it 'returns 0 when all tests pass', ->
      { code } = yield run { test: 'passing' }
      code.should.equal 0

    it 'returns a failing code equal to the number of mocha failures', ->
      { code } = yield run { test: 'failing' }
      code.should.equal 3

    it 'returns a failing code correctly even with async failing tests', ->
      { code } = yield run { test: 'failing-async' }
      code.should.equal 3

  describe 'screenshot', ->
    it 'takes a screenshot into given file, suffixed with .png', ->
      { code } = yield run { test: 'screenshot' }
      code.should.equal 0
      fileName = 'screenshot.png'
      fs.existsSync(fileName).should.be.true
      fs.unlinkSync(fileName)

  describe 'third party reporters', ->
    it 'loads and wraps node-style reporters to run in the browser', ->
      { stdout } = yield run
        reporter: process.cwd() + '/test/reporters/3rd-party.js'
        test: 'mixed'

      stdout.should.match /<section class="suite">/
      stdout.should.match /<h1>Tests Mixed<\/h1>/

    it 'can be referenced relatively', ->
      { stdout } = yield run
        reporter: './test/reporters/3rd-party.js'
        test: 'mixed'

      stdout.should.match /<section class="suite">/
      stdout.should.match /<h1>Tests Mixed<\/h1>/

    it 'gives a useful error when trying to require a node module', ->
      { code, stderr } = yield run
        reporter: process.cwd() + '/test/reporters/node-only.js'
        test: 'mixed'

      stderr.should.match /Node modules cannot be required/
      code.should.not.equal 0      

  describe 'hooks', ->
    it 'should fail gracefully if they do not exist', ->
      { code, stderr } = yield run
        hooks: 'nonexistant-file.js'

      code.should.not.equal 0
      stderr.should.contain "Error loading hooks: Cannot find module 'nonexistant-file.js'"
    
    describe 'before start', ->
      it 'is called', ->
        { code, stdout } = yield run
          hooks: process.cwd() + '/test/hooks/before-start.js'

        stdout.should.contain 'Before start called!'
        code.should.equal 0

    describe 'after end', ->
      it 'is called', ->
        { code, stdout } = yield run
          hooks: process.cwd() + '/test/hooks/after-end.js'
        
        stdout.should.contain 'After end called!'
        code.should.equal 0


  describe 'config', ->
    describe 'user-agent', ->
      it 'has the default user agent', ->
        { stdout } = yield run { test: 'user-agent' }
        stdout.should.match /PhantomJS\//

      it 'has a custom user agent via settings', ->
        { stdout } = yield run
          test: 'user-agent'
          settings: 
            userAgent: 'mocha=UserAgent'

        stdout.should.match /^mocha=UserAgent/

    describe 'cookies', ->
      # https://github.com/nathanboktae/mocha-phantomjs-core/issues/4
      it 'has passed cookies', !process.env.PHANTOMJS2 and ->
        { stdout } = yield run
          test: 'cookie'
          cookies: [
            { name: 'foo', value: 'bar' },
            { name: 'baz', value: 'bat', path: '/' }
          ]

        stdout.should.match /foo=bar; baz=bat/

    describe 'viewport', ->
      it 'has the specified dimensions', ->
        { stdout } = yield run
          test: 'viewport'
          viewportSize: 
            width: 123
            height: 456

        stdout.should.match /123x456/

    describe 'grep', ->
      it 'filters tests to match the criteria', ->
        { code, stdout } = yield run
          test: 'mixed'
          grep: 'pass'

        code.should.equal 0
        stdout.should.not.match /fail/

      it 'can be inverted to filter out tests matching the criteria', ->
        { code, stdout } = yield run
          test: 'mixed'
          grep: 'pass'
          invert: true

        code.should.equal 6
        stdout.should.not.match /passes/

    describe 'colors', ->
      it 'can force output in color', ->
        { stdout } = yield run
          reporter: 'dot'
          test: 'mixed'
          useColors: true
        
        stdout.should.match /\u001b\[90m\․\u001b\[0m/ # grey
        stdout.should.match /\u001b\[36m\․\u001b\[0m/ # cyan
        stdout.should.match /\u001b\[31m\․\u001b\[0m/ # red

      it 'can suppresses color output', ->
        { stdout } = yield run
          test: 'mixed'
          useColors: false

        stdout.should.not.match /\u001b\[\d\dm/

    describe 'bail', ->
      it 'should bail on the first error', ->
        { stdout } = yield run
          test: 'mixed'
          bail: true

        stdout.should.contain '1 failing'

    describe 'file', ->
      it 'pipes reporter output to a file', ->
        { stdout } = yield run
          test: 'file'
          reporter: 'json'
          file: 'reporteroutput.json'

        stdout.should.contain 'Extraneous'
        results = JSON.parse fs.readFileSync 'reporteroutput.json', { encoding: 'utf8' }
        results.passes.length.should.equal 6
        results.failures.length.should.equal 6

      after ->
        fs.unlinkSync 'reporteroutput.json'

    describe 'ignore resource errors', ->
      it 'by default shows resource errors', ->
        { code, stderr } = yield run { test: 'resource-errors' }
        stderr.should.contain('Error loading resource').and.contain('nonexistant-file.css')
        code.should.equal 0

      it 'can suppress resource errors', ->
        { stderr } = yield run { test: 'resource-errors', ignoreResourceErrors: true }
        stderr.should.be.empty

  describe 'env', ->
    it 'has passed environment variables', ->
      process.env.FOO = 'yowzer'
      { stdout } = yield run { test: 'env' }
      stdout.should.match /^yowzer/
