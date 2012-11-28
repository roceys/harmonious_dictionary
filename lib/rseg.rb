$KCODE = 'UTF8'

require 'singleton'
require 'net/http'
require 'yaml'

require File.join(File.dirname(__FILE__), 'engines/engine')
require File.join(File.dirname(__FILE__), 'engines/dict')
require File.join(File.dirname(__FILE__), 'engines/english')

require File.join(File.dirname(__FILE__), 'filters/fullwidth')
require File.join(File.dirname(__FILE__), 'filters/symbol')
require File.join(File.dirname(__FILE__), 'filters/conjunction')

class Rseg
  include Singleton
  include RsegEngine
  include RsegFilter
  
  class << self
    def dict_path=(path)
      RsegEngine::Dict.dict_path = path
    end
    
    def segment(input)
      Rseg.instance.input = input
      Rseg.instance.segment
    end
    
    def load
      Rseg.instance
      nil
    end
    
    def remote_segment(input)
      begin
        response = Net::HTTP.post_form(URI.parse('http://127.0.0.1:4100/seg'), :input => input)
        response.code == '200' ? response.body.split(' ') : 
            ["Can't connect to http://localhost:4100\nUse rseg_server to start it"]
      rescue
        ["Can't connect to http://localhost:4100\nUse rseg_server to start it"]
      end
    end
  end

  def initialize
    @input = ''
    @words = []
    init_engines
    init_filters
    @english_dictionary = YAML.load(english_yaml_path)
  end
  
  def input=(input)
    @input = input
  end
  
  def segment
    @words = []
    #拆分每个字
    @input.chars.each do |origin|
      char = filter(origin) # 过滤，标记分割词或特殊字符
      process(char, origin)
    end
    
    process(:symbol, '')
    @words
  end

  private
  
  def filter(char)
    result = char
    @filters.each do |klass|
      result = klass.filter(result)
    end
    result
  end
  
  def process(char, origin)
    nomatch = true
    word = ''
    
    engines.each do |engine|
      next unless engine.running?
      match, word = engine.process(char)
      if match 
       nomatch = false
     else
      word = '' if engine.class == English && !@english_dictionary.include?(word)
      engine.stop 
     end
    end
    
    if nomatch
      if word == ''
        # 没切出来的就当正常的词，不输出
        # @words << origin unless char == :symbol 
        reset_engines
      else
        reset_engines
        @words << word if word.is_a?(String) && word.size > 3
        # 我们只需要脏词完全匹配，不需要检查下文
        # reprocess(word) if word.is_a?(Array)
        # re-process current char
        process(char, origin)
      end
    end
  end
  
  def reprocess(word)
    last = word.pop

    word.each do |char|
      process(char, char)
    end
    
    process(:symbol, :symbol) # 把词加进来
    process(last, last) # 继续分析词的最后一个字符
  end

  def reset_engines
    engines.each do |engine|
      engine.run
    end
  end
  
  def engines=(engines)
    @engines ||= engines
  end

  def engines
    @engines
  end

  def init_filters
    @filters = [Fullwidth, Symbol]
  end
  
  def init_engines
    @engines ||= [Dict, English].map do |engine_klass|
      engine_klass.new
    end
  end

  def english_yaml_path
    File.read(File.join(File.dirname(__FILE__), '../dictionary/english.yml'))
  end
end
