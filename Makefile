# directories
TARGET = target
PREFIX = $(PWD)/$(TARGET)

# tools
CHMOD = chmod
CP = cp
MKDIR = mkdir
RM = rm
SED = sed

.PHONY: all clean

all: $(TARGET)/provider.yaml

$(TARGET):
	$(MKDIR) -p $@

$(TARGET)/provider.sh: provider.sh | $(TARGET)
	$(CP) $< $@
	$(CHMOD) a+x $@

$(TARGET)/provider.yaml: provider.yaml $(TARGET)/provider.sh | $(TARGET)
	$(SED) -e 's#@prefix@#$(PREFIX)#g' -e "s#@hash@#`sha256 -q '$(TARGET)/provider.sh'`#g" $< >$@

clean:
	$(RM) -rf $(TARGET)
