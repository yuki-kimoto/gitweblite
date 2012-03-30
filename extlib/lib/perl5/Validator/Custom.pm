package Validator::Custom;
use Object::Simple -base;
use 5.008001;
our $VERSION = '0.1426';

use Carp 'croak';
use Validator::Custom::Constraint;
use Validator::Custom::Result;

has ['data_filter', 'rule'],
  error_stock => 1;

has syntax => <<'EOS';
### Syntax of validation rule
my $rule = [                              # 1 Rule is array ref
  key => [                              # 2 Constraints is array ref
      'constraint',                     # 3 Constraint is string
      {'constraint' => 'args'}          #     or hash ref (arguments)
      ['constraint', 'err'],            #     or arrya ref (message)
  ],
  key => [                           
      [{constraint => 'args'}, 'err']   # 4 With argument and message
  ],
  {key => ['key1', 'key2']} => [        # 5.1 Multi-parameters validation
      'constraint'
  ],
  {key => qr/^key/} => [                # 5.2 Multi-parameters validation
      'constraint'                              using regular expression
  ],
  key => [
      '@constraint'                     # 6 Multi-values validation
  ],
  key => {message => 'err', ... } => [  # 7 With options
      'constraint'
  ],
  key => [
      '!constraint'                     # 8 Negativate constraint
  ],
  key => [
      'constraint1 || constraint2'      # 9 "OR" condition
  ],
];

EOS

sub js_fill_form_button {
  my ($self, $rule) = @_;
  
  my $r = $self->_parse_random_string_rule($rule);
  
  require JSON;
  my $r_json = JSON->new->encode($r);
  
  my $javascript = << "EOS";
(function () {

  var rule = $r_json;

  var create_random_value = function (rule, name) {
    var patterns = rule[name];
    if (patterns === undefined) {
      return "";
    }
    
    var value = "";
    for (var i = 0; i < patterns.length; i++) {
      var pattern = patterns[i];
      var num = Math.floor(Math.random() * pattern.length);
      value = value + pattern[num];
    }
    
    return value;
  };
  
	var addEvent = (function(){
	  if(document.addEventListener) {
	    return function(node,type,handler){
	      node.addEventListener(type,handler,false);
	    };
	  } else if (document.attachEvent) {
	    return function(node,type,handler){
	      node.attachEvent('on' + type, function(evt){
	        handler.call(node, evt);
	      });
	    };
	  }
	})();
	
	var button = document.createElement("input");
	button.setAttribute("type","button");
	button.value = "Fill Form";
  document.body.insertBefore(button, document.body.firstChild)

  addEvent(
    button,
    "click",
    function () {
      
      var input_elems = document.getElementsByTagName('input');
      var radio_names = {};
      var checkbox_names = {};
      for (var i = 0; i < input_elems.length; i++) {
        var e = input_elems[i];

        var name = e.getAttribute("name");
        var type = e.getAttribute("type");
        if (type === "text" || type === "hidden" || type === "password") {
          var value = create_random_value(rule, name);
          e.value = value;
        }
        else if (type === "checkbox") {
          e.checked = Math.floor(Math.random() * 2) ? true : false;
        }
        else if (type === "radio") {
          radio_names[name] = 1;
        }
      }
      
      for (name in radio_names) {
        var elems = document.getElementsByName(name);
        var num = Math.floor(Math.random() * elems.length);
        elems[num].checked = true;
      }
      
      var textarea_elems = document.getElementsByTagName("textarea");
      for (var i = 0; i < textarea_elems.length; i++) {
        var e = textarea_elems[i];
        
        var name = e.getAttribute("name");
        var value = create_random_value(rule, name);
        
        var text = document.createTextNode(value);
        
        if (e.firstChild) {
          e.removeChild(e.firstChild);
        }
        
        e.appendChild(text);
      }
      
      var select_elems = document.getElementsByTagName("select");
      for (var i = 0; i < select_elems.length; i++) {
        var e = select_elems[i];
        var options = e.options;
        if (e.multiple) {
          for (var k = 0; k < options.length; k++) {
            options[k].selected = Math.floor(Math.random() * 2) ? true : false;
          }
        }
        else {
          var num = Math.floor(Math.random() * options.length);
          e.selectedIndex = num;
        }
      }
    }
  );
})();
EOS

  return $javascript;
}

sub new {
  my $self = shift->SUPER::new(@_);

  $self->register_constraint(
    any               => sub { 1 },
    ascii             => \&Validator::Custom::Constraint::ascii,
    between           => \&Validator::Custom::Constraint::between,
    blank             => \&Validator::Custom::Constraint::blank,
    date_to_timepiece => \&Validator::Custom::Constraint::date_to_timepiece,
    datetime_to_timepiece => \&Validator::Custom::Constraint::datetime_to_timepiece,
    decimal           => \&Validator::Custom::Constraint::decimal,
    defined           => sub { defined $_[0] },
    duplication       => \&Validator::Custom::Constraint::duplication,
    equal_to          => \&Validator::Custom::Constraint::equal_to,
    greater_than      => \&Validator::Custom::Constraint::greater_than,
    http_url          => \&Validator::Custom::Constraint::http_url,
    int               => \&Validator::Custom::Constraint::int,
    in_array          => \&Validator::Custom::Constraint::in_array,
    length            => \&Validator::Custom::Constraint::length,
    less_than         => \&Validator::Custom::Constraint::less_than,
    merge             => \&Validator::Custom::Constraint::merge,
    not_defined       => \&Validator::Custom::Constraint::not_defined,
    not_space         => \&Validator::Custom::Constraint::not_space,
    not_blank         => \&Validator::Custom::Constraint::not_blank,
    uint              => \&Validator::Custom::Constraint::uint,
    regex             => \&Validator::Custom::Constraint::regex,
    selected_at_least => \&Validator::Custom::Constraint::selected_at_least,
    shift             => \&Validator::Custom::Constraint::shift_array,
    space             => \&Validator::Custom::Constraint::space,
    to_array          => \&Validator::Custom::Constraint::to_array,
    trim              => \&Validator::Custom::Constraint::trim,
    trim_collapse     => \&Validator::Custom::Constraint::trim_collapse,
    trim_lead         => \&Validator::Custom::Constraint::trim_lead,
    trim_trail        => \&Validator::Custom::Constraint::trim_trail
  );
  
  return $self;
}

sub register_constraint {
  my $self = shift;
  
  # Merge
  my $constraints = ref $_[0] eq 'HASH' ? $_[0] : {@_};
  $self->constraints({%{$self->constraints}, %$constraints});
  
  return $self;
}

our %VALID_OPTIONS = map {$_ => 1} qw/message default copy require/;

sub validate {
  my ($self, $data, $rule) = @_;
  
  # Class
  my $class = ref $self;
  
  # Validation rule
  $rule ||= $self->rule;
  
  # Shared rule
  my $shared_rule = $self->shared_rule;
  
  # Data filter
  my $filter = $self->data_filter;
  $data = $filter->($data) if $filter;
  
  # Check data
  croak "First argument must be hash ref"
    unless ref $data eq 'HASH';
  
  # Check rule
  croak "Validation rule must be array ref\n" .
      "(see syntax of validation rule 1)\n" .
      $self->_rule_syntax($rule)
    unless ref $rule eq 'ARRAY';
  
  # Result
  my $result = Validator::Custom::Result->new;
  $result->{_error_infos} = {};
  
  # Save raw data
  $result->raw_data($data);
  
  # Error is stock?
  my $error_stock = $self->error_stock;
  
  # Valid keys
  my $valid_keys = {};
  
  # Error position
  my $pos = 0;
  
  # Found missing paramteters
  my $found_missing_params = {};

  # Process each key
  OUTER_LOOP:
  for (my $i = 0; $i < @{$rule}; $i += 2) {
    
    # Increment position
    $pos++;
    
    # Key, options, and constraints
    my $key = $rule->[$i];
    my $opts = $rule->[$i + 1];
    my $constraints;
    if (ref $opts eq 'HASH') {
      $constraints = $rule->[$i + 2];
      $i++;
    }
    else {
      $constraints = $opts;
      $opts = {};
    }
    
    # Check constraints
    croak "Constraints of validation rule must be array ref\n" .
        "(see syntax of validation rule 2)\n" . $self->_rule_syntax($rule)
      unless ref $constraints eq 'ARRAY';
    
    # Arrange key
    my $result_key = $key;
    if (ref $key eq 'HASH') {
      my $first_key = (keys %$key)[0];
      $result_key = $first_key;
      $key         = $key->{$first_key};
    }
    
    # Real keys
    my $keys;
    
    if (ref $key eq 'ARRAY') { $keys = $key }
    elsif (ref $key eq 'Regexp') {
      $keys = [];
      foreach my $k (keys %$data) {
         push @$keys, $k if $k =~ /$key/;
      }
    }
    else { $keys = [$key] }
    
    # Check option
    foreach my $oname (keys %$opts) {
      croak qq{Option "$oname" of "$result_key" is invalid name}
        unless $VALID_OPTIONS{$oname};
    }
    
    # Is data copy?
    my $copy = 1;
    $copy = $opts->{copy} if exists $opts->{copy};
    
    # Check missing parameters
    my $require = exists $opts->{require} ? $opts->{require} : 1;
    my $found_missing_param;
    my $missing_params = $result->missing_params;
    foreach my $key (@$keys) {
      unless (exists $data->{$key}) {
        if ($require) {
          push @$missing_params, $key
            unless $found_missing_params->{$key};
          $found_missing_params->{$key}++;
        }
        $found_missing_param = 1;
      }
    }
    if ($found_missing_param) {
      $result->data->{$result_key} = ref $opts->{default} eq 'CODE'
          ? $opts->{default}->($self) : $opts->{default}
        if exists $opts->{default} && $copy;
      next;
    }
    
    # Already valid
    next if $valid_keys->{$result_key};
    
    # Add shared rule
    push @$constraints, @$shared_rule;
    
    # Validation
    my $value = @$keys > 1
      ? [map { $data->{$_} } @$keys]
      : $data->{$keys->[0]};

    foreach my $constraint (@$constraints) {
      
      # Arrange constraint information
      my ($constraint, $message)
        = ref $constraint eq 'ARRAY' ? @$constraint : ($constraint);
      
      # Data type
      my $data_type = {};
      
      # Arguments
      my $arg;
      
      # Arrange constraint
      if(ref $constraint eq 'HASH') {
        my $first_key = (keys %$constraint)[0];
        $arg        = $constraint->{$first_key};
        $constraint = $first_key;
      }
      
      # Constraint function
      my $cfuncs;
      my $negative;
      
      # Sub reference
      if( ref $constraint eq 'CODE') {
        # Constraint function
        $cfuncs = [$constraint];
      }
      
      # Constraint key
      else {
        # Constirnt infomation
        my $cinfo = $self->_parse_constraint($constraint);
        $data_type->{array} = 1 if $cinfo->{array};
                                        
        # Constraint function
        $cfuncs = $cinfo->{funcs};
      }
      
      # Is valid?
      my $is_valid;
      
      # Data is array
      if($data_type->{array}) {
          
        # To array
        $value = [$value] unless ref $value eq 'ARRAY';
        
        # Validation loop
        for (my $i = 0; $i < @$value; $i++) {
          my $data = $value->[$i];
          
          # Validation
          for (my $k = 0; $k < @$cfuncs; $k++) {
            my $cfunc = $cfuncs->[$k];
            
            # Validate
            my $cresult = $cfunc->($data, $arg, $self);
            
            # Constrint result
            my $v;
            if (ref $cresult eq 'ARRAY') {
              ($is_valid, $v) = @$cresult;
              $value->[$i] = $v;
            }
            else { $is_valid = $cresult }
            
            last if $is_valid;
          }
          
          # Validation error
          last unless $is_valid;
        }
      }
      
      # Data is scalar
      else {
        # Validation
        foreach my $cfunc (@$cfuncs) {
          my $cresult = $cfunc->($value, $arg, $self);
          
          if (ref $cresult eq 'ARRAY') {
            my $v;
            ($is_valid, $v) = @$cresult;
            $value = $v if $is_valid;
          }
          else { $is_valid = $cresult }
          
          last if $is_valid;
        }
      }
      
      # Add error if it is invalid
      unless ($is_valid) {
        # Resist error info
        $message = $opts->{message} unless defined $message;
        $result->{_error_infos}->{$result_key} = {
          message      => $message,
          position     => $pos,
          reason       => $constraint,
          original_key => $key
        } unless exists $result->{_error_infos}->{$result_key};
        
        # Set default value
        $result->data->{$result_key} = ref $opts->{default} eq 'CODE'
                                     ? $opts->{default}->($self)
                                     : $opts->{default}
          if exists $opts->{default} && $copy;
        
        # No Error strock
        unless ($error_stock) {
          # Check rest constraint
          my $found;
          for (my $k = $i + 2; $k < @{$rule}; $k += 2) {
            my $key = $rule->[$k];
            $k++ if ref $rule->[$k + 1] eq 'HASH';
            $key = (keys %$key)[0] if ref $key eq 'HASH';
            $found = 1 if $key eq $result_key;
          }
          last OUTER_LOOP unless $found;
        }
        next OUTER_LOOP;
      }
    }
    
    # Result data
    $result->data->{$result_key} = $value if $copy;
    
    # Key is valid
    $valid_keys->{$result_key} = 1;
    
    # Remove invalid key
    delete $result->{_error_infos}->{$key};
  }
  
  return $result;
}

sub _parse_constraint {
  my ($self, $constraint) = @_;
  
  # Constraint infomation
  my $cinfo = {};
  
  # Simple constraint name
  unless ($constraint =~ /\W/) {
    my $cfunc = $self->constraints->{$constraint} || '';
    croak qq{"$constraint" is not registered}
      unless ref $cfunc eq 'CODE';
    $cinfo->{funcs} = [$cfunc];
    return $cinfo;
  }

  # Trim space
  $constraint ||= '';
  $constraint =~ s/^\s+//;
  $constraint =~ s/\s+$//;
  
  # Target is array elemetns
  $cinfo->{array} = 1 if $constraint =~ s/^@//;
  croak qq{"\@" must be one at the top of constrinat name}
    if index($constraint, '@') > -1;
  
  # Constraint functions
  my @cfuncs;
  
  # Constraint names
  my @cnames = split(/\|\|/, $constraint);
  
  # Convert constarint names to constraint funcions
  foreach my $cname (@cnames) {
    $cname ||= '';
    
    # Trim space
    $cname =~ s/^\s+//;
    $cname =~ s/\s+$//;
    
    # Negative
    my $negative = $cname =~ s/^!// ? 1 : 0;
    croak qq{"!" must be one at the top of constraint name}
      if index($cname, '!') > -1;
    
    # Trim space
    $cname =~ s/^\s+//;
    $cname =~ s/\s+$//;
    
    # Constraint function
    croak "Constraint name '$cname' must be [A-Za-z0-9_]"
      if $cname =~ /\W/;
    my $cfunc = $self->constraints->{$cname} || '';
    croak qq{"$cname" is not registered}
      unless ref $cfunc eq 'CODE';
    
    # Negativate
    my $f = $negative ? sub {
      my $ret = $cfunc->(@_);
      if (ref $ret eq 'ARRAY') {
        $ret->[0] = ! $ret->[0];
        return $ret;
      }
      else { return !$ret }
    } : $cfunc;
    
    # Add
    push @cfuncs, $f;
  }
  
  $cinfo->{funcs} = \@cfuncs;
  
  return $cinfo;
}

sub _parse_random_string_rule {
  my $self = shift;
  
  # Rule
  my $rule = ref $_[0] eq 'HASH' ? $_[0] : {@_};
  
  # Result
  my $result = {};
  
  # Parse string rule
  foreach my $name (keys %$rule) {
    # Pettern
    my $pattern = $rule->{$name};
    $pattern = '' unless $pattern;
    
    # State
    my $state = 'character';

    # Count
    my $count = '';
    
    # Chacacter sets
    my $csets = [];
    my $cset = [];
    
    # Parse pattern
    my $c;
    while (defined ($c = substr($pattern, 0, 1, '')) && length $c) {
      # Character class
      if ($state eq 'character_class') {
        if ($c eq ']') {
          $state = 'character';
          push @$csets, $cset;
          $cset = [];
          $state = 'character';
        }
        else { push @$cset, $c }
      }
      
      # Count
      elsif ($state eq 'count') {
        if ($c eq '}') {
          $count = 1 if $count < 1;
          for (my $i = 0; $i < $count - 1; $i++) {
              push @$csets, [@{$csets->[-1] || ['']}];
          }
          $count = '';
          $state = 'character';
        }
        else { $count .= $c }
      }
      
      # Character
      else {
        if ($c eq '[') { $state = 'character_class' }
        elsif ($c eq '{') { $state = 'count' }
        else { push @$csets, [$c] }
      }
    }
    
    # Add Charcter sets
    $result->{$name} = $csets;
  }
  
  return $result;
}

sub _rule_syntax {
  my ($self, $rule) = @_;
  
  my $message = $self->syntax;
  
  require Data::Dumper;
  $message .= "### Your validation rule:\n";
  $message .= Data::Dumper->Dump([$rule], ['$rule']);
  $message .= "\n";
  return $message;
}

# DEPRECATED!
has shared_rule => sub { [] };
# DEPRECATED!
__PACKAGE__->dual_attr('constraints',
  default => sub { {} }, inherit => 'hash_copy');

1;

=head1 NAME

Validator::Custom - Validate user input easily

=head1 SYNOPSYS

  use Validator::Custom;
  my $vc = Validator::Custom->new;

  my $data = {age => 19, name => 'Ken Suzuki'};
  
  my $rule = [
    age => {message => 'age must be integer'} => [
      'not_blank',
      'int'
    ],
    name => {message => 'name must be string. the length 1 to 5'} => [
      'not_blank',
      {length => [1, 5]}
    ],
    price => [
      'not_blank',
      'int'
    ]
  ];
  
  my $result = $vc->validate($data, $rule);

  unless ($result->is_ok) {
    if ($result->has_missing) {
      my $missing_params = $result->missing_params;
    }
    
    if ($result->has_invalid) {
      my $messages = $result->messages_to_hash;
    }
  }
  my $valid_data = $result->data;
  my $raw_data = $result->raw_data;
  my $loose_data = $result->loose_data;

  
=head1 DESCRIPTION

L<Validator::Custom> validate user input easily.
The features are the following ones.

=over 4

=item *

Many constraint functions are available by default, such as C<not_blank>,
C<int>, C<defined>, C<in_array>, C<length>.

=item *

Several filter functions are available by default, such as C<trim>,
C<datetime_to_timepiece>, C<date_to_timepiece>.

=item *

You can register your constraint function.

=item *

You can set error messages for invalid parameter value.
The order of messages is keeped.

=item *

Support C<OR> condtion constraint, Negativate constraint,

=back

=head1 GUIDE

L<Validator::Custom::Guide> - L<Validator::Custom> Guide

=head1 ATTRIBUTES

=head2 C<constraints>

  my $constraints = $vc->constraints;
  $vc             = $vc->constraints(\%constraints);

Constraint functions.

=head2 C<data_filter>

  my $filter = $vc->data_filter;
  $vc        = $vc->data_filter(\&data_filter);

Filter for input data. If data is not hash reference, you can convert
the data to hash reference.

  $vc->data_filter(sub {
    my $data = shift;
    
    my $hash = {};
    
    # Convert data to hash reference
    
    return $hash;
  });

=head2 C<error_stock>

  my $error_stock = $vc->error_stcok;
  $vc             = $vc->error_stock(1);

If error_stock is set to 0, C<validate()> return soon after invalid value is found.

Default to 1. 

=head2 C<rule>

  my $rule = $vc->rule;
  $vc      = $vc->rule(\@rule);

Validation rule. If second argument of C<validate()> is not specified.
this rule is used.

=head2 C<syntax>

  my $syntax = $vc->syntax;
  $vc        = $vc->syntax($syntax);

Syntax of rule.

=head1 METHODS

L<Validator::Custom> inherits all methods from L<Object::Simple>
and implements the following new ones.

=head2 C<new>

  my $vc = Validator::Custom->new;

Create a new L<Validator::Custom> object.

=head2 C<js_fill_form_button>

  my $button = $self->js_fill_form_button(
    mail => '[abc]{3}@[abc]{2}.com,
    title => '[pqr]{5}'
  );

Create javascript button source code to fill form.
You can specify string or pattern like regular expression.

If you click this button, each text box is filled with the
specified pattern string,
and checkbox, radio button, and list box is automatically selected.

Note that this methods require L<JSON> module.

=head2 C<validate>

  $result = $vc->validate($data, $rule);
  $result = $vc->validate($data);

Validate the data.
Return value is L<Validator::Custom::Result> object.
If second argument is not specified,
C<rule> attribute is used.

=head2 C<register_constraint>

  $vc->register_constraint(%constraint);
  $vc->register_constraint(\%constraint);

Register constraint function.
  
  $vc->register_constraint(
    int => sub {
      my $value    = shift;
      my $is_valid = $value =~ /^\-?[\d]+$/;
      return $is_valid;
    },
    ascii => sub {
      my $value    = shift;
      my $is_valid = $value =~ /^[\x21-\x7E]+$/;
      return $is_valid;
    }
  );

You can register filter function.

  $vc->register_constraint(
    trim => sub {
      my $value = shift;
      $value =~ s/^\s+//;
      $value =~ s/\s+$//;
      
      return [1, $value];
    }
  );

Filter function return array reference,
first element is the value if the value is valid or not,
second element is the converted value by filter function.

=head1 RULE SYNTAX

Validation rule has the following syntax.

  # Rule syntax
  my $rule = [                          # 1 Rule is array ref
    key => [                            # 2 Constraints is array ref
      'constraint',                     # 3 Constraint is string
      {'constraint' => 'args'}          #     or hash ref (arguments)
      ['constraint', 'err'],            #     or arrya ref (message)
    ],
    key => [                           
      [{constraint => 'args'}, 'err']   # 4 With argument and message
    ],
    {key => ['key1', 'key2']} => [      # 5.1 Multi-parameters validation
      'constraint'
    ],
    {key => qr/^key/} => [              # 5.2 Multi-parameters validation
      'constraint'                            using regular expression
    ],
    key => [
      '@constraint'                     # 6 Multi-values validation
    ],
    key => {message => 'err', ... } => [# 7 With option
      'constraint'
    ],
    key => [
      '!constraint'                     # 8 Negativate constraint
    ],
    key => [
      'constraint1 || constraint2'      # 9 "OR" condition constraint
    ],
  ];

Rule can have option, following options is available.

=over 4

=item 1. message

  {message => "Input right value"}

Message for invalid value.

=item 2. default

  {default => 5}

Default value, set to C<data> of C<Validator::Custom::Result>
when invalid value or missing value is found

=item 3. copy

  {copy => 0}

If C<copy> is 0, the value is not copied to C<data> of C<Validator::Custom::Result>. 

Default to 1. 

=item 4. require

  {require => 0}

If C<require> is 0,
The value is not appended to missing parameter list
even if the value is not found

Default to 1.

=back

=head1 CONSTRAINTS

=head2 C<ascii>

  my $data => {name => 'Ken'};
  my $rule = [
    name => [
      'ascii'
    ]
  ];

Ascii.

=head2 C<between>

  my $data = {age => 19};
  my $rule = [
    age => [
      {between => [1, 20]} # (1, 2, .. 19, 20)
    ]
  ];

Between A and B.

=head2 C<blank>

  my $data = {name => ''};
  my $rule = [
    name => [
      'blank'
    ]
  ];

Blank.

=head2 C<decimal>
  
  my $data = {num1 => '123', num2 => '1.45'};
  my $rule => [
    num1 => [
      {'decimal' => 3}
    ],
    num2 => [
      {'decimal' => [1, 2]}
    ]
  ];

Decimal. You can specify maximus digits number at before
and after '.'.

=head2 C<defined>

  my $data => {name => 'Ken'};
  my $rule = [
    name => [
      'defined'
    ]
  ];

Defined.

=head2 C<duplication>

  my $data = {mail1 => 'a@somehost.com', mail2 => 'a@somehost.com'};
  my $rule => [
    {mail => ['mail1', 'mail2']} => [
      'duplication'
    ]
  ];

Check if the two data are same or not.

Note that if one value is not defined or both values are not defined,
result of validation is false.

=head2 C<equal_to>

  my $data = {price => 1000};
  my $rule = [
    price => [
      {'equal_to' => 1000}
    ]
  ];

Numeric equal comparison.

=head2 C<greater_than>

  my $data = {price => 1000};
  my $rule = [
    price => [
      {'greater_than' => 900}
    ]
  ];

Numeric "greater than" comparison

=head2 C<http_url>

  my $data = {url => 'http://somehost.com'};
  my $rule => [
    url => [
      'http_url'
    ]
  ];

HTTP(or HTTPS) URL.

=head2 C<int>

  my $data = {age => 19};
  my $rule = [
    age => [
      'int'
    ]
  ];

Integer.

=head2 C<in_array>

  my $data = {food => 'sushi'};
  my $rule = [
    food => [
      {'in_array' => [qw/sushi bread apple/]}
    ]
  ];

Check if the values is in array.

=head2 C<length>

  my $data = {value1 => 'aaa', value2 => 'bbbbb'};
  my $rule => [
    value1 => [
      {'length' => 3}
    ],
    value2 => [
      {'length' => [2, 5]} # 'bb' to 'bbbbb'
    ]
  ];

Length of the value.

=head2 C<less_than>

  my $data = {num => 20};
  my $rule = [
    num => [
      {'less_than' => 25}
    ]
  ];

Numeric "less than" comparison.

=head2 C<not_blank>

  my $data = {name => 'Ken'};
  my $rule = [
    name => [
      'not_blank' # Except for ''
    ]
  ];

Not blank.

=head2 C<not_defined>

  my $data = {name => 'Ken'};
  my $rule = [
    name => [
      'not_defined'
    ]
  ];

Not defined.

=head2 C<not_space>

  my $data = {name => 'Ken'};
  my $rule = [
    name => [
      'not_space' # Except for '', ' ', '   '
    ]
  ];

Not contain only space characters. 

=head2 C<space>

  my $data = {name => '   '};
  my $rule = [
    name => [
      'space' # '', ' ', '   '
    ]
  ];

White space or empty stirng.

=head2 C<uint>

  my $data = {age => 19};
  my $rule = [
    age => [
      'uint'
    ]
  ];

Unsigned integer.
  
=head2 C<regex>

  my $data = {num => '123'};
  my $rule => [
    num => [
      {'regex' => qr/\d{0,3}/}
    ]
  ];

Match a regular expression.

=head2 C<selected_at_least>

  my $data = {hobby => ['music', 'movie' ]};
  my $rule => [
    hobby => [
      {selected_at_least => 1}
    ]
  ];

Selected at least specified count item.
In other word, the array contains at least specified count element.

=head1 FILTERS

=head2 C<date_to_timepiece>

  my $data = {date => '2010/11/12'};
  my $rule = [
    date => [
      'date_to_timepiece'
    ]
  ];

The value which looks like date is converted
to L<Time::Piece> object.
If the value contains 8 digits, the value is assumed date.

  2010/11/12 # ok
  2010-11-12 # ok
  20101112   # ok
  2010       # NG
  2010111106 # NG

And year and month and mday combination is ok.

  my $data = {year => 2011, month => 3, mday => 9};
  my $rule = [
    {date => ['year', 'month', 'mday']} => [
      'date_to_timepiece'
    ]
  ];

Note that L<Time::Piece> is required.

=head2 C<datetime_to_timepiece>

  my $data = {datetime => '2010/11/12 12:14:45'};
  my $rule = [
    datetime => [
      'datetime_to_timepiece'
    ]
  ];

The value which looks like date and time is converted
to L<Time::Piece> object.
If the value contains 14 digits, the value is assumed date and time.

  2010/11/12 12:14:45 # ok
  2010-11-12 12:14:45 # ok
  20101112 121445     # ok
  2010                # NG
  2010111106 12       # NG

And year and month and mday combination is ok.

  my $data = {year => 2011, month => 3, mday => 9
              hour => 10, min => 30, sec => 30};
  my $rule = [
    {datetime => ['year', 'month', 'mday', 'hour', 'min', 'sec']} => [
      'datetime_to_timepiece'
    ]
  ];

Note that L<Time::Piece> is required.

=head2 C<merge>

  my $data = {name1 => 'Ken', name2 => 'Rika', name3 => 'Taro'};
  my $rule = [
    {merged_name => ['name1', 'name2', 'name3']} => [
      'merge' # KenRikaTaro
    ]
  ];

Merge the values.
Note that if one value is not defined, merged value become undefined.

=head2 C<shift>

  my $data = {names => ['Ken', 'Taro']};
  my $rule => [
    names => [
      'shift' # 'Ken'
    ]
  ];

Shift the head element of array.

=head2 C<to_array>

  my $data = {languages => 'Japanese'};
  my $rule = [
    languages => [
      'to_array' # ['Japanese']
    ],
  ];
  
Convert non array reference data to array reference.
This is useful to check checkbox values or select multiple values.

=head2 C<trim>

  my $data = {name => '  Ken  '};
  my $rule = [
    name => [
      'trim' # 'Ken'
    ]
  ];

Trim leading and trailing white space.

=head2 C<trim_collapse>

  my $data = {name => '  Ken   Takagi  '};
  my $rule = [
    name => [
      'trim_collapse' # 'Ken Takagi'
    ]
  ];

Trim leading and trailing white space,
and collapse all whitespace characters into a single space.

=head2 C<trim_lead>

  my $data = {name => '  Ken  '};
  my $rule = [
    name => [
      'trim_lead' # 'Ken  '
    ]
  ];

Trim leading white space.

=head2 C<trim_trail>

  my $data = {name => '  Ken  '};
  my $rule = [
    name => [
      'trim_trail' # '  Ken'
    ]
  ];

Trim trailing white space.

=head1 DEPRECATED FUNCTIONALITIES

L<Validator::Custom>
  
  # Atrribute methods
  shared_rule # Removed at 2017/1/1
  
  # Methods
  __PACKAGE__->constraints(...); # Call constraints method as class method
                                 # Removed at 2017/1/1
L<Validator::Custom::Result>

  # Attribute methods
  error_infos # Removed at 2017/1/1 

  # Methods
  add_error_info # Removed at 2017/1/1
  error # Removed at 2017/1/1
  errors # Removed at 2017/1/1
  errors_to_hash # Removed at 2017/1/1
  invalid_keys # Removed at 2017/1/1
  remove_error_info# Removed at 2017/1/1

=head1 BACKWORD COMPATIBLE POLICY

If a functionality is DEPRECATED, you can know it by DEPRECATED warnings
except for attribute method.
You can check all DEPRECATED functionalities by document.
DEPRECATED functionality is removed after five years,
but if at least one person use the functionality and tell me that thing
I extend one year each time you tell me it.

EXPERIMENTAL functionality will be changed without warnings.

This policy is changed at 2011/6/28

=head1 AUTHOR

Yuki Kimoto, C<< <kimoto.yuki at gmail.com> >>

L<http://github.com/yuki-kimoto/Validator-Custom>

=head1 COPYRIGHT & LICENCE

Copyright 2009-2011 Yuki Kimoto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
