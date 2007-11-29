require 'camping/db'
require 'openwfe/util/scheduler'

module Taskr::Models

  class Task < Base
    has_many :task_actions
    
    serialize :schedule_options
    
    validates_presence_of :schedule_method
    validates_presence_of :schedule_when
    validates_presence_of :name
    validates_uniqueness_of :name
    validates_presence_of :task_actions
    validates_associated :task_actions
    
    def schedule!(scheduler)
      case schedule_method
      when 'cron'
        method = :schedule
      when 'at'
        method = :schedule_at
      when 'in'
        method = :schedule_in
      when 'every'
        method = :schedule_every
      end
      
      $LOG.debug "Scheduling task #{name.inspect}: #{self.inspect}"
      
      if task_actions.length == 1
        ta = task_actions.first
        
        parameters = {}
        ta.action_parameters.each{|p| parameters[p.name] = p.value}
        
        action = (ta.action_class.kind_of?(Class) ? ta.action_class : ta.action_class.constantize).new(parameters)
        action.task = self
      elsif task_actions.length > 1
        action = Taskr::Actions::Multi.new
        task_actions.each do |ta|
          parameters = {}
          ta.action_parameters.each{|p| parameters[p.name] = p.value}
          
          a = (ta.action_class.kind_of?(Class) ? ta.action_class : ta.action_class.constantize).new(parameters)
          a.task = self
          
          action.actions << a 
        end
      else
        $LOG.warn "Task #{name.inspect} has no actions and as a result will not be scheduled!"
        return false
      end
      
      job_id = scheduler.send(method, schedule_when, :schedulable => action)
      
      $LOG.debug "Task #{name.inspect} scheduled with job id #{job_id}"
  
      self.update_attribute(:scheduler_job_id, job_id)
      
      return job_id
    end
    
    def to_s
      "#<#{self.class}:#{self.id}>"
    end
  end
  
  class TaskAction < Base
    belongs_to :task
    
    has_many :action_parameters, 
      :class_name => 'TaskActionParameter', 
      :foreign_key => :task_action_id
    
    validates_associated :action_parameters
    
    def action_class=(class_name)
      if class_name.kind_of? Class
        self[:action_class_name] = class_name.to_s
      else
        self[:action_class_name] = class_name
      end
    end
    
    def action_class
      self[:action_class_name].constantize
    end
    
    def to_s
      "#<#{self.class}:#{self.id}>"
    end
  end

  class TaskActionParameter < Base
    belongs_to :task_action
    serialize :value
    
    def to_s
      "#<#{self.class}:#{self.id}>"
    end
  end

  class CreateTaskr < V 0.1
    def self.up
      $LOG.info("Migrating database")
      
      create_table :taskr_tasks, :force => true do |t|
        t.column :name, :string, :null => false
        t.column :created_on, :timestamp, :null => false
        t.column :created_by, :string
        
        t.column :schedule_method, :string, :null => false
        t.column :schedule_when, :string, :null => false
        t.column :schedule_options, :text
        
        t.column :scheduler_job_id, :integer
      end
      
      add_index :taskr_tasks, [:name], :unique => true
      
      create_table :taskr_task_actions, :force => true do |t|
        t.column :task_id, :integer, :null => false
        t.column :action_class_name, :string, :null => false
        t.column :order, :integer
      end
      
      add_index :taskr_task_actions, [:task_id]
      
      create_table :taskr_task_action_parameters, :force => true do |t|
        t.column :task_action_id, :integer, :null => false
        t.column :name, :string, :null => false
        t.column :value, :text
      end
      
      add_index :taskr_task_action_parameters, [:task_action_id]
      add_index :taskr_task_action_parameters, [:task_action_id, :name]
    end
    
    def self.down
      drop_table :taskr_task_action_parameters
      drop_table :taskr_tasks
    end
  end
end