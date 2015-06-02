$LOAD_PATH.unshift File.expand_path('../../../lib', __FILE__)
require 'message_bus'
require 'sinatra'
require 'sinatra/base'
require 'set'
require 'json'

$redis = Redis.new

$online = Hash.new
MessageBus.subscribe "/presence" do |msg|
  if user = msg.data["enter"]
     $online[user] = Time.now
  end
  if user = msg.data["leave"]
     $online.delete user
  end
end

class Chat < Sinatra::Base

  set :public_folder,  File.expand_path('../../../assets',__FILE__)

  use MessageBus::Rack::Middleware

  post '/enter' do
    name = params["name"]
    i = 1
    while $online.include? name
      name = "#{params["name"]}#{i}"
      i += 1
    end
    MessageBus.publish '/presence', {enter: params["name"]}
    {users: $online.keys, name: name}.to_json
  end

  post '/leave' do
    MessageBus.publish '/presence', {leave: params["name"]}
  end

  post '/message' do
    msg = {data: params["data"][0..500], name: params["name"][0..100]}
    MessageBus.publish '/message', msg

    "OK"
  end

  get '/' do

<<HTML

<html>
  <head>
    <script src="/jquery-1.8.2.js"></script>
    <script src="/message-bus.js"></script>
    <style>
        #panel { position: fixed; bottom: 0; background-color: #FFFFFF; }
        #messages { padding-bottom: 40px; }
        .hidden { display: none; }
        #users {
         position: fixed; top: 0; right: 0; width: 160px; background-color: #fafafa; height: 100%;
         border-left: 1px solid #dfdfdf;
         padding: 5px;
        }
        #users ul li {  margin: 0; padding: 0; }
        #users ul { list-style: none; margin 0; padding: 0; }
        body { padding-right: 160px; }
    </style>
  </head>
  <body>
    <p>This is a trivial chat demo... It is implemented as a <a href="https://github.com/SamSaffron/message_bus/blob/master/examples/chat/chat.rb">Sinatra app</a>. The <a href="https://github.com/SamSaffron/message_bus">message_bus</a> can easily be added to any Rails/Rack app. <small>This app can be deployed with <a href="https://github.com/discourse/discourse_docker">Discourse Docker</a> using <a href="https://github.com/SamSaffron/message_bus/blob/master/examples/chat/docker_container/chat.yml">this template</a>.</small></p>
    <div id='messages' class="hidden"></div>
    <div id='users' class="hidden">
      <h3>Online</h3>
      <ul></ul>
    </div>
    <div id='panel' class="hidden">
      <form>
        <textarea cols=80 rows=2></textarea>
        <button id="send">send</button>
      </form>
    </div>
    <div id='your-name'>Enter your name: <input type='text'/>

    <script>
      $(function() {
        var name;

        var enter = function(name, opts) {
           if (opts && opts.check) {
             var found = false;
             $('#users ul li').each(function(){
                found = found || ($(this).text().trim() === name.trim());
                return !found;
             });
             if (found) { return; }
           }

           var li = $('<li></li>');
           li.text(name);
           $('#users ul').append(li);
        };

        $('#messages, #panel').addClass('hidden');

        $('#your-name input').keyup(function(e){
          if(e.keyCode == 13) {
            name = $(this).val();
            $.post("/enter", { name: name}, null, "json" ).success(function(data){
              $.each(data.users,function(idx, name){
                enter(name);
              });
              name = data.name;
              $('#send').text("send (" + name + ")");
              enter(name, {check: true});
            });
            $('#your-name').addClass('hidden');
            $('#messages, #panel, #users').removeClass('hidden');

            window.onbeforeunload = function(){
              $.post("/leave", { name: name });
            };

            MessageBus.subscribe("/presence", function(msg){
              if (msg.enter) {
                 enter(msg.enter, {check: true});
              }
              if (msg.leave) {
               $('#users ul li').each(function(){
                  if ($(this).text() === msg.leave) {
                    $(this).remove()
                  }
               });
              }
            });
          }
        });

        var safe = function(html){
           return String(html).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
        };

        MessageBus.subscribe("/message", function(msg){
          $('#messages').append("<p>"+ safe(msg.name) + " said: " + safe(msg.data) + "</p>");
          $(document.body).scrollTop(document.body.scrollHeight);
        }, 0); // last id is zero, so getting backlog

        var submit = function(){
          var val = $('form textarea').val().trim();
          if (val.length === 0) {
            return;
          }

          if (val.length > 500) {
            alert("message too long");
            return false;
          } else {
            $.post("/message", { data: val, name: name} );
          }
          $('textarea').val("");
        };

        $('#send').click(function(){submit(); return false;});

        $('textarea').keyup(function(e){
          if(e.keyCode == 13) {
            submit();
          }
        });

      });
    </script>
  </body>
</html>

HTML
  end

  run! if app_file == $0
end
